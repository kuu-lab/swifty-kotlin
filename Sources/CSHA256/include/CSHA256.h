#ifndef KSWIFTK_SHA256_H
#define KSWIFTK_SHA256_H

#include <stddef.h>
#include <stdint.h>

// One-shot SHA-256 (FIPS 180-4) for compiler-side content fingerprints.
// Kept dependency-free so debug (unoptimized) compiler builds do not pay the
// cost of a byte-at-a-time pure-Swift fallback on artifact-sized inputs.
// `data` may be NULL when `length` is 0. `digest` receives 32 bytes.
void kswiftk_sha256(const uint8_t *data, size_t length, uint8_t digest[32]);

#endif
