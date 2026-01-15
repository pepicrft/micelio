#ifndef HIF_GRPC_CLIENT_H
#define HIF_GRPC_CLIENT_H

#include <stddef.h>
#include <stdint.h>

int hif_grpc_unary_call(const char *target,
                        const char *host,
                        const char *method,
                        const uint8_t *request,
                        size_t request_len,
                        const char *auth_token,
                        int use_tls,
                        uint8_t **response_out,
                        size_t *response_len_out,
                        char **error_out);

void hif_grpc_free(void *ptr);

#endif
