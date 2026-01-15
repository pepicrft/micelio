#include "grpc/client.h"

#include <grpc/grpc.h>
#include <grpc/credentials.h>
#include <grpc/byte_buffer_reader.h>
#include <grpc/support/alloc.h>
#include <grpc/support/time.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void hif_grpc_free(void *ptr) {
    if (ptr != NULL) {
        gpr_free(ptr);
    }
}

static char *dup_cstring(const char *value) {
    if (value == NULL) {
        return NULL;
    }
    size_t len = strlen(value);
    char *copy = gpr_malloc(len + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, value, len);
    copy[len] = '\0';
    return copy;
}

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
    if (response_out == NULL || response_len_out == NULL || error_out == NULL) {
        return 1;
    }

    *response_out = NULL;
    *response_len_out = 0;
    *error_out = NULL;

    grpc_init();

    grpc_channel_credentials *creds = NULL;
    if (use_tls) {
        creds = grpc_ssl_credentials_create(NULL, NULL, NULL, NULL);
        if (creds == NULL) {
            *error_out = dup_cstring("Failed to create TLS credentials.");
            grpc_shutdown();
            return 1;
        }
    } else {
        creds = grpc_insecure_credentials_create();
        if (creds == NULL) {
            *error_out = dup_cstring("Failed to create insecure credentials.");
            grpc_shutdown();
            return 1;
        }
    }

    grpc_channel *channel = grpc_channel_create(target, creds, NULL);
    grpc_channel_credentials_release(creds);

    if (channel == NULL) {
        *error_out = dup_cstring("Failed to create gRPC channel.");
        grpc_shutdown();
        return 1;
    }

    grpc_completion_queue *cq = grpc_completion_queue_create_for_next(NULL);
    if (cq == NULL) {
        *error_out = dup_cstring("Failed to create completion queue.");
        grpc_channel_destroy(channel);
        grpc_shutdown();
        return 1;
    }

    grpc_slice method_slice = grpc_slice_from_copied_string(method);
    grpc_slice host_slice = grpc_slice_from_copied_string(host);
    gpr_timespec deadline = gpr_time_add(gpr_now(GPR_CLOCK_REALTIME), gpr_time_from_seconds(20, GPR_TIMESPAN));

    grpc_call *call = grpc_channel_create_call(channel, NULL, GRPC_PROPAGATE_DEFAULTS, cq, method_slice, &host_slice, deadline, NULL);
    grpc_slice_unref(method_slice);
    grpc_slice_unref(host_slice);

    if (call == NULL) {
        *error_out = dup_cstring("Failed to create gRPC call.");
        grpc_completion_queue_destroy(cq);
        grpc_channel_destroy(channel);
        grpc_shutdown();
        return 1;
    }

    grpc_metadata meta[1];
    size_t meta_count = 0;
    grpc_slice auth_value_slice;
    char *auth_value = NULL;

    if (auth_token != NULL && auth_token[0] != '\0') {
        size_t auth_len = strlen(auth_token);
        auth_value = gpr_malloc(auth_len + 8);
        if (auth_value != NULL) {
            snprintf(auth_value, auth_len + 8, "Bearer %s", auth_token);
            meta[0].key = grpc_slice_from_static_string("authorization");
            auth_value_slice = grpc_slice_from_copied_string(auth_value);
            meta[0].value = auth_value_slice;
            meta_count = 1;
        }
    }

    grpc_byte_buffer *request_buffer = NULL;
    if (request != NULL && request_len > 0) {
        grpc_slice request_slice = grpc_slice_from_copied_buffer((const char *)request, request_len);
        request_buffer = grpc_raw_byte_buffer_create(&request_slice, 1);
        grpc_slice_unref(request_slice);
    }

    grpc_metadata_array initial_metadata;
    grpc_metadata_array trailing_metadata;
    grpc_metadata_array_init(&initial_metadata);
    grpc_metadata_array_init(&trailing_metadata);

    grpc_byte_buffer *response_payload = NULL;
    grpc_status_code status = GRPC_STATUS_UNKNOWN;
    grpc_slice status_details = grpc_slice_from_static_string("");

    grpc_op ops[6];
    memset(ops, 0, sizeof(ops));

    ops[0].op = GRPC_OP_SEND_INITIAL_METADATA;
    ops[0].data.send_initial_metadata.count = meta_count;
    ops[0].data.send_initial_metadata.metadata = meta_count > 0 ? meta : NULL;

    ops[1].op = GRPC_OP_SEND_MESSAGE;
    ops[1].data.send_message.send_message = request_buffer;

    ops[2].op = GRPC_OP_SEND_CLOSE_FROM_CLIENT;

    ops[3].op = GRPC_OP_RECV_INITIAL_METADATA;
    ops[3].data.recv_initial_metadata.recv_initial_metadata = &initial_metadata;

    ops[4].op = GRPC_OP_RECV_MESSAGE;
    ops[4].data.recv_message.recv_message = &response_payload;

    ops[5].op = GRPC_OP_RECV_STATUS_ON_CLIENT;
    ops[5].data.recv_status_on_client.trailing_metadata = &trailing_metadata;
    ops[5].data.recv_status_on_client.status = &status;
    ops[5].data.recv_status_on_client.status_details = &status_details;

    grpc_call_error call_error = grpc_call_start_batch(call, ops, 6, (void *)1, NULL);
    if (call_error != GRPC_CALL_OK) {
        *error_out = dup_cstring("Failed to start gRPC call.");
    } else {
        grpc_event event = grpc_completion_queue_next(cq, deadline, NULL);
        if (event.type != GRPC_OP_COMPLETE || event.success == 0) {
            *error_out = dup_cstring("gRPC call did not complete.");
        } else if (status != GRPC_STATUS_OK) {
            const char *details = grpc_slice_to_c_string(status_details);
            if (details != NULL && details[0] != '\0') {
                *error_out = dup_cstring(details);
            } else {
                *error_out = dup_cstring("gRPC call failed.");
            }
            gpr_free((void *)details);
        } else if (response_payload != NULL) {
            grpc_byte_buffer_reader reader;
            if (grpc_byte_buffer_reader_init(&reader, response_payload)) {
                grpc_slice response_slice = grpc_byte_buffer_reader_readall(&reader);
                size_t len = GRPC_SLICE_LENGTH(response_slice);
                uint8_t *buffer = gpr_malloc(len);
                if (buffer == NULL) {
                    *error_out = dup_cstring("Failed to allocate response buffer.");
                } else {
                    memcpy(buffer, GRPC_SLICE_START_PTR(response_slice), len);
                    *response_out = buffer;
                    *response_len_out = len;
                }
                grpc_slice_unref(response_slice);
                grpc_byte_buffer_reader_destroy(&reader);
            } else {
                *error_out = dup_cstring("Failed to read gRPC response.");
            }
        } else {
            *error_out = dup_cstring("Empty gRPC response.");
        }
    }

    if (request_buffer != NULL) {
        grpc_byte_buffer_destroy(request_buffer);
    }

    grpc_metadata_array_destroy(&initial_metadata);
    grpc_metadata_array_destroy(&trailing_metadata);

    if (meta_count > 0) {
        grpc_slice_unref(auth_value_slice);
    }

    if (auth_value != NULL) {
        gpr_free(auth_value);
    }

    if (response_payload != NULL) {
        grpc_byte_buffer_destroy(response_payload);
    }

    grpc_slice_unref(status_details);
    grpc_call_unref(call);

    grpc_completion_queue_shutdown(cq);
    while (grpc_completion_queue_next(cq, gpr_inf_future(GPR_CLOCK_REALTIME), NULL).type != GRPC_QUEUE_SHUTDOWN) {
    }
    grpc_completion_queue_destroy(cq);
    grpc_channel_destroy(channel);
    grpc_shutdown();

    return *error_out == NULL ? 0 : 1;
}
