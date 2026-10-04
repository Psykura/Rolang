#ifndef ROLANG_STD_CRYPTO_H
#define ROLANG_STD_CRYPTO_H

#include "../runtime/abi.h"
#include "string.h"

void* rt_crypto_failure(void);
void* rt_crypto_random_bytes(int32_t count);
int32_t rt_crypto_equal(void* a, void* b);
void* rt_crypto_hasher_new(void* name);
int32_t rt_crypto_hasher_update(void* context, void* data);
void* rt_crypto_hasher_finish(void* context);
void rt_crypto_hasher_free(void* context);
void* rt_crypto_hmac(void* name, void* key, void* data);
void* rt_crypto_pbkdf2(void* name, void* password, void* salt, int32_t iterations, int32_t length);
void* rt_crypto_seal(void* name, void* key, void* nonce, void* plaintext, void* aad);
void* rt_crypto_open(void* name, void* key, void* nonce, void* sealed, void* aad);

#endif /* ROLANG_STD_CRYPTO_H */
