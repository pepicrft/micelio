/*
 * Lightweight gRPC client using nghttp2 + OpenSSL
 * Replaces the heavy gRPC C++ library (1.1GB -> ~200KB dependencies)
 */

#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "client.h"

#include <nghttp2/nghttp2.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/bio.h>

#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <sys/time.h>

/* gRPC framing: 1 byte compression flag + 4 bytes big-endian length */
#define GRPC_HEADER_SIZE 5

typedef struct {
    SSL_CTX *ssl_ctx;
    SSL *ssl;
    BIO *bio;
    int fd;
    int use_tls;
    nghttp2_session *session;
    
    /* Request data */
    const uint8_t *request_data;
    size_t request_len;
    size_t request_sent;
    int request_stream_id;
    
    /* Response data */
    uint8_t *response_data;
    size_t response_len;
    size_t response_capacity;
    size_t response_expected_len;
    int response_complete;
    
    /* Error handling */
    char *error_message;
    int grpc_status;
} grpc_connection;

static void set_error(grpc_connection *conn, const char *msg) {
    if (conn->error_message) free(conn->error_message);
    conn->error_message = strdup(msg);
}

static char *dup_string(const char *s) {
    if (!s) return NULL;
    return strdup(s);
}

void hif_grpc_free(void *ptr) {
    free(ptr);
}

/* Socket I/O for nghttp2 */
static ssize_t conn_send(grpc_connection *conn, const uint8_t *data, size_t len) {
    if (conn->use_tls) {
        int ret = SSL_write(conn->ssl, data, (int)len);
        if (ret <= 0) {
            int err = SSL_get_error(conn->ssl, ret);
            if (err == SSL_ERROR_WANT_WRITE || err == SSL_ERROR_WANT_READ) {
                return NGHTTP2_ERR_WOULDBLOCK;
            }
            return NGHTTP2_ERR_CALLBACK_FAILURE;
        }
        return ret;
    } else {
        ssize_t ret = write(conn->fd, data, len);
        if (ret < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return NGHTTP2_ERR_WOULDBLOCK;
            }
            return NGHTTP2_ERR_CALLBACK_FAILURE;
        }
        return ret;
    }
}

static ssize_t conn_recv(grpc_connection *conn, uint8_t *data, size_t len) {
    if (conn->use_tls) {
        int ret = SSL_read(conn->ssl, data, (int)len);
        if (ret <= 0) {
            int err = SSL_get_error(conn->ssl, ret);
            if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
                return NGHTTP2_ERR_WOULDBLOCK;
            }
            if (err == SSL_ERROR_ZERO_RETURN) {
                return NGHTTP2_ERR_EOF;
            }
            return NGHTTP2_ERR_CALLBACK_FAILURE;
        }
        return ret;
    } else {
        ssize_t ret = read(conn->fd, data, len);
        if (ret < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return NGHTTP2_ERR_WOULDBLOCK;
            }
            return NGHTTP2_ERR_CALLBACK_FAILURE;
        }
        if (ret == 0) {
            return NGHTTP2_ERR_EOF;
        }
        return ret;
    }
}

/* nghttp2 callbacks */
static ssize_t send_callback(nghttp2_session *session, const uint8_t *data,
                             size_t length, int flags, void *user_data) {
    (void)session; (void)flags;
    grpc_connection *conn = (grpc_connection *)user_data;
    return conn_send(conn, data, length);
}

static ssize_t recv_callback(nghttp2_session *session, uint8_t *buf,
                             size_t length, int flags, void *user_data) {
    (void)session; (void)flags;
    grpc_connection *conn = (grpc_connection *)user_data;
    return conn_recv(conn, buf, length);
}

static int on_frame_recv_callback(nghttp2_session *session,
                                  const nghttp2_frame *frame, void *user_data) {
    (void)session;
    grpc_connection *conn = (grpc_connection *)user_data;
    
    if (frame->hd.stream_id == conn->request_stream_id) {
        if (frame->hd.type == NGHTTP2_HEADERS && 
            frame->hd.flags & NGHTTP2_FLAG_END_STREAM) {
            conn->response_complete = 1;
        }
    }
    return 0;
}

static int on_data_chunk_recv_callback(nghttp2_session *session, uint8_t flags,
                                       int32_t stream_id, const uint8_t *data,
                                       size_t len, void *user_data) {
    (void)session; (void)flags;
    grpc_connection *conn = (grpc_connection *)user_data;
    
    if (stream_id != conn->request_stream_id) return 0;
    
    /* Grow response buffer if needed */
    size_t needed = conn->response_len + len;
    if (needed > conn->response_capacity) {
        size_t new_cap = conn->response_capacity * 2;
        if (new_cap < needed) new_cap = needed;
        if (new_cap < 4096) new_cap = 4096;
        uint8_t *new_buf = realloc(conn->response_data, new_cap);
        if (!new_buf) return NGHTTP2_ERR_CALLBACK_FAILURE;
        conn->response_data = new_buf;
        conn->response_capacity = new_cap;
    }
    
    memcpy(conn->response_data + conn->response_len, data, len);
    conn->response_len += len;

    if (conn->response_expected_len == 0 && conn->response_len >= GRPC_HEADER_SIZE) {
        uint32_t msg_len = (conn->response_data[1] << 24) |
                           (conn->response_data[2] << 16) |
                           (conn->response_data[3] << 8) |
                           (conn->response_data[4]);
        conn->response_expected_len = GRPC_HEADER_SIZE + msg_len;
    }

    if (conn->response_expected_len > 0 && conn->response_len >= conn->response_expected_len) {
        conn->response_complete = 1;
    }

    return 0;
}

static int on_stream_close_callback(nghttp2_session *session, int32_t stream_id,
                                    uint32_t error_code, void *user_data) {
    (void)session; (void)error_code;
    grpc_connection *conn = (grpc_connection *)user_data;
    
    if (stream_id == conn->request_stream_id) {
        conn->response_complete = 1;
    }
    return 0;
}

static int on_header_callback(nghttp2_session *session, const nghttp2_frame *frame,
                              const uint8_t *name, size_t namelen,
                              const uint8_t *value, size_t valuelen,
                              uint8_t flags, void *user_data) {
    (void)session; (void)flags;
    grpc_connection *conn = (grpc_connection *)user_data;
    
    if (frame->hd.stream_id != conn->request_stream_id) return 0;
    
    /* Check for grpc-status header in trailers */
    if (namelen == 11 && memcmp(name, "grpc-status", 11) == 0) {
        conn->grpc_status = atoi((const char *)value);
        conn->response_complete = 1;
    } else if (namelen == 12 && memcmp(name, "grpc-message", 12) == 0) {
        if (conn->error_message) free(conn->error_message);
        conn->error_message = strndup((const char *)value, valuelen);
    }
    
    return 0;
}

/* Data provider for request body */
static ssize_t data_source_read_callback(nghttp2_session *session, int32_t stream_id,
                                         uint8_t *buf, size_t length,
                                         uint32_t *data_flags,
                                         nghttp2_data_source *source,
                                         void *user_data) {
    (void)session; (void)stream_id; (void)source;
    grpc_connection *conn = (grpc_connection *)user_data;
    
    size_t remaining = conn->request_len - conn->request_sent;
    size_t to_send = remaining < length ? remaining : length;
    
    memcpy(buf, conn->request_data + conn->request_sent, to_send);
    conn->request_sent += to_send;
    
    if (conn->request_sent >= conn->request_len) {
        *data_flags |= NGHTTP2_DATA_FLAG_EOF;
    }
    
    return (ssize_t)to_send;
}

/* Connect to server */
static int connect_to_server(grpc_connection *conn, const char *host, int port) {
    struct addrinfo hints = {0}, *res, *rp;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);
    
    int ret = getaddrinfo(host, port_str, &hints, &res);
    if (ret != 0) {
        set_error(conn, gai_strerror(ret));
        return -1;
    }
    
    for (rp = res; rp != NULL; rp = rp->ai_next) {
        conn->fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (conn->fd < 0) continue;
        
        if (connect(conn->fd, rp->ai_addr, rp->ai_addrlen) == 0) break;
        
        close(conn->fd);
        conn->fd = -1;
    }
    
    freeaddrinfo(res);
    
    if (conn->fd < 0) {
        set_error(conn, "Failed to connect to server");
        return -1;
    }

    /* Disable Nagle's algorithm for lower latency */
    int flag = 1;
    setsockopt(conn->fd, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    setsockopt(conn->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(conn->fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    return 0;
}

/* Setup TLS */
static int setup_tls(grpc_connection *conn, const char *host) {
    SSL_library_init();
    SSL_load_error_strings();
    
    conn->ssl_ctx = SSL_CTX_new(TLS_client_method());
    if (!conn->ssl_ctx) {
        set_error(conn, "Failed to create SSL context");
        return -1;
    }
    
    /* Use system CA certificates */
    SSL_CTX_set_default_verify_paths(conn->ssl_ctx);
    SSL_CTX_set_verify(conn->ssl_ctx, SSL_VERIFY_PEER, NULL);
    
    /* Enable ALPN for HTTP/2 */
    unsigned char alpn[] = "\x02h2";
    SSL_CTX_set_alpn_protos(conn->ssl_ctx, alpn, sizeof(alpn) - 1);
    
    conn->ssl = SSL_new(conn->ssl_ctx);
    if (!conn->ssl) {
        set_error(conn, "Failed to create SSL object");
        return -1;
    }
    
    /* Set SNI hostname */
    SSL_set_tlsext_host_name(conn->ssl, host);
    
    /* Connect SSL to socket */
    SSL_set_fd(conn->ssl, conn->fd);
    
    int ret = SSL_connect(conn->ssl);
    if (ret != 1) {
        char buf[256];
        ERR_error_string_n(ERR_get_error(), buf, sizeof(buf));
        set_error(conn, buf);
        return -1;
    }
    
    /* Verify ALPN negotiated HTTP/2 */
    const unsigned char *alpn_out;
    unsigned int alpn_len;
    SSL_get0_alpn_selected(conn->ssl, &alpn_out, &alpn_len);
    if (alpn_len != 2 || memcmp(alpn_out, "h2", 2) != 0) {
        set_error(conn, "Server did not negotiate HTTP/2");
        return -1;
    }
    
    return 0;
}

/* Setup nghttp2 session */
static int setup_http2(grpc_connection *conn) {
    nghttp2_session_callbacks *callbacks;
    nghttp2_session_callbacks_new(&callbacks);
    
    nghttp2_session_callbacks_set_send_callback(callbacks, send_callback);
    nghttp2_session_callbacks_set_recv_callback(callbacks, recv_callback);
    nghttp2_session_callbacks_set_on_frame_recv_callback(callbacks, on_frame_recv_callback);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(callbacks, on_data_chunk_recv_callback);
    nghttp2_session_callbacks_set_on_stream_close_callback(callbacks, on_stream_close_callback);
    nghttp2_session_callbacks_set_on_header_callback(callbacks, on_header_callback);
    
    int ret = nghttp2_session_client_new(&conn->session, callbacks, conn);
    nghttp2_session_callbacks_del(callbacks);
    
    if (ret != 0) {
        set_error(conn, "Failed to create HTTP/2 session");
        return -1;
    }
    
    /* Send HTTP/2 client connection preface and SETTINGS */
    nghttp2_settings_entry settings[] = {
        {NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 100},
        {NGHTTP2_SETTINGS_INITIAL_WINDOW_SIZE, 65535}
    };
    
    ret = nghttp2_submit_settings(conn->session, NGHTTP2_FLAG_NONE, settings, 2);
    if (ret != 0) {
        set_error(conn, "Failed to submit SETTINGS");
        return -1;
    }
    
    return 0;
}

/* Build gRPC-framed request */
static uint8_t *build_grpc_request(const uint8_t *message, size_t message_len, size_t *out_len) {
    size_t total = GRPC_HEADER_SIZE + message_len;
    uint8_t *buf = malloc(total);
    if (!buf) return NULL;
    
    /* gRPC header: compression flag (0) + 4-byte big-endian length */
    buf[0] = 0; /* no compression */
    buf[1] = (message_len >> 24) & 0xFF;
    buf[2] = (message_len >> 16) & 0xFF;
    buf[3] = (message_len >> 8) & 0xFF;
    buf[4] = message_len & 0xFF;
    
    if (message_len > 0 && message) {
        memcpy(buf + GRPC_HEADER_SIZE, message, message_len);
    }
    
    *out_len = total;
    return buf;
}

/* Parse gRPC response */
static int parse_grpc_response(const uint8_t *data, size_t len,
                               uint8_t **message_out, size_t *message_len_out) {
    if (len < GRPC_HEADER_SIZE) return -1;
    
    /* Skip compression flag */
    uint32_t message_len = ((uint32_t)data[1] << 24) |
                           ((uint32_t)data[2] << 16) |
                           ((uint32_t)data[3] << 8) |
                           (uint32_t)data[4];
    
    if (len < GRPC_HEADER_SIZE + message_len) return -1;
    
    *message_out = malloc(message_len);
    if (!*message_out) return -1;
    
    memcpy(*message_out, data + GRPC_HEADER_SIZE, message_len);
    *message_len_out = message_len;
    return 0;
}

/* Main gRPC unary call function */
int hif_grpc_unary_call(const char *target,
                        const char *host,
                        const char *method,
                        const uint8_t *request,
                        size_t request_len,
                        const char *auth_token,
                        int use_tls,
                        uint8_t **response_out,
                        size_t *response_len_out,
                        char **error_out) {
    if (!response_out || !response_len_out || !error_out) return 1;
    
    *response_out = NULL;
    *response_len_out = 0;
    *error_out = NULL;
    
    grpc_connection conn = {0};
    conn.use_tls = use_tls;
    conn.fd = -1;
    conn.grpc_status = -1;
    
    /* Parse target (host:port) */
    char *target_copy = strdup(target);
    char *colon = strrchr(target_copy, ':');
    int port = use_tls ? 443 : 80;
    char *hostname = target_copy;
    
    if (colon) {
        *colon = '\0';
        port = atoi(colon + 1);
    }
    
    /* Connect */
    if (connect_to_server(&conn, hostname, port) != 0) {
        *error_out = dup_string(conn.error_message);
        free(target_copy);
        if (conn.error_message) free(conn.error_message);
        return 1;
    }
    
    /* Setup TLS if needed */
    if (use_tls) {
        if (setup_tls(&conn, hostname) != 0) {
            *error_out = dup_string(conn.error_message);
            close(conn.fd);
            free(target_copy);
            if (conn.error_message) free(conn.error_message);
            return 1;
        }
    }
    
    free(target_copy);
    
    /* Setup HTTP/2 */
    if (setup_http2(&conn) != 0) {
        *error_out = dup_string(conn.error_message);
        goto cleanup;
    }
    
    /* Build gRPC-framed request */
    size_t grpc_request_len;
    uint8_t *grpc_request = build_grpc_request(request, request_len, &grpc_request_len);
    if (!grpc_request) {
        *error_out = dup_string("Failed to build gRPC request");
        goto cleanup;
    }
    
    conn.request_data = grpc_request;
    conn.request_len = grpc_request_len;
    conn.request_sent = 0;
    
    /* Build HTTP/2 headers */
    char authority[256];
    snprintf(authority, sizeof(authority), "%s", host);
    
    char content_length[32];
    snprintf(content_length, sizeof(content_length), "%zu", grpc_request_len);
    
    char auth_header[1024];
    if (auth_token && auth_token[0]) {
        snprintf(auth_header, sizeof(auth_header), "Bearer %s", auth_token);
    }
    
    nghttp2_nv headers[8];
    int header_count = 0;
    
    headers[header_count++] = (nghttp2_nv){
        (uint8_t *)":method", (uint8_t *)"POST", 7, 4, NGHTTP2_NV_FLAG_NONE
    };
    headers[header_count++] = (nghttp2_nv){
        (uint8_t *)":scheme", (uint8_t *)(use_tls ? "https" : "http"),
        7, use_tls ? 5 : 4, NGHTTP2_NV_FLAG_NONE
    };
    headers[header_count++] = (nghttp2_nv){
        (uint8_t *)":path", (uint8_t *)method,
        5, strlen(method), NGHTTP2_NV_FLAG_NONE
    };
    headers[header_count++] = (nghttp2_nv){
        (uint8_t *)":authority", (uint8_t *)authority,
        10, strlen(authority), NGHTTP2_NV_FLAG_NONE
    };
    headers[header_count++] = (nghttp2_nv){
        (uint8_t *)"content-type", (uint8_t *)"application/grpc",
        12, 16, NGHTTP2_NV_FLAG_NONE
    };
    headers[header_count++] = (nghttp2_nv){
        (uint8_t *)"te", (uint8_t *)"trailers",
        2, 8, NGHTTP2_NV_FLAG_NONE
    };
    
    if (auth_token && auth_token[0]) {
        headers[header_count++] = (nghttp2_nv){
            (uint8_t *)"authorization", (uint8_t *)auth_header,
            13, strlen(auth_header), NGHTTP2_NV_FLAG_NONE
        };
    }
    
    /* Setup data provider */
    nghttp2_data_provider data_prd;
    data_prd.source.ptr = &conn;
    data_prd.read_callback = data_source_read_callback;
    
    /* Submit request */
    conn.request_stream_id = nghttp2_submit_request(
        conn.session, NULL, headers, header_count, &data_prd, &conn
    );
    
    if (conn.request_stream_id < 0) {
        *error_out = dup_string("Failed to submit HTTP/2 request");
        free(grpc_request);
        goto cleanup;
    }
    
    /* Send/receive loop */
    struct timespec start_time;
    clock_gettime(CLOCK_MONOTONIC, &start_time);

    while (!conn.response_complete) {
        int ret = nghttp2_session_send(conn.session);
        if (ret != 0) {
            *error_out = dup_string(nghttp2_strerror(ret));
            free(grpc_request);
            goto cleanup;
        }
        
        ret = nghttp2_session_recv(conn.session);
        if (ret != 0 && ret != NGHTTP2_ERR_EOF) {
            *error_out = dup_string(nghttp2_strerror(ret));
            free(grpc_request);
            goto cleanup;
        }
        
        if (ret == NGHTTP2_ERR_EOF) break;

        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long elapsed_ms =
            (now.tv_sec - start_time.tv_sec) * 1000L + (now.tv_nsec - start_time.tv_nsec) / 1000000L;

        if (elapsed_ms > 3000 && conn.response_len > 0) {
            conn.response_complete = 1;
        } else if (elapsed_ms > 10000) {
            *error_out = dup_string("gRPC request timed out");
            free(grpc_request);
            goto cleanup;
        }
    }
    
    free(grpc_request);
    
    /* Check gRPC status */
    if (conn.grpc_status != 0 && conn.grpc_status != -1) {
        if (conn.error_message) {
            *error_out = dup_string(conn.error_message);
        } else {
            char buf[64];
            snprintf(buf, sizeof(buf), "gRPC error: status %d", conn.grpc_status);
            *error_out = dup_string(buf);
        }
        goto cleanup;
    }
    
    /* Parse gRPC response */
    if (conn.response_len > 0) {
        uint8_t *message;
        size_t message_len;
        if (parse_grpc_response(conn.response_data, conn.response_len,
                               &message, &message_len) == 0) {
            *response_out = message;
            *response_len_out = message_len;
        } else {
            *error_out = dup_string("Failed to parse gRPC response");
        }
    }

cleanup:
    if (conn.response_data) free(conn.response_data);
    if (conn.error_message) free(conn.error_message);
    if (conn.session) nghttp2_session_del(conn.session);
    if (conn.ssl) SSL_free(conn.ssl);
    if (conn.ssl_ctx) SSL_CTX_free(conn.ssl_ctx);
    if (conn.fd >= 0) close(conn.fd);
    
    return *error_out ? 1 : 0;
}
