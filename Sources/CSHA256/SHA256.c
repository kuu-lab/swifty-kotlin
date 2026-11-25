#include "CSHA256.h"

#include <string.h>

static const uint32_t kSwiftKSHA256K[64] = {
    0x428A2F98U, 0x71374491U, 0xB5C0FBCFU, 0xE9B5DBA5U,
    0x3956C25BU, 0x59F111F1U, 0x923F82A4U, 0xAB1C5ED5U,
    0xD807AA98U, 0x12835B01U, 0x243185BEU, 0x550C7DC3U,
    0x72BE5D74U, 0x80DEB1FEU, 0x9BDC06A7U, 0xC19BF174U,
    0xE49B69C1U, 0xEFBE4786U, 0x0FC19DC6U, 0x240CA1CCU,
    0x2DE92C6FU, 0x4A7484AAU, 0x5CB0A9DCU, 0x76F988DAU,
    0x983E5152U, 0xA831C66DU, 0xB00327C8U, 0xBF597FC7U,
    0xC6E00BF3U, 0xD5A79147U, 0x06CA6351U, 0x14292967U,
    0x27B70A85U, 0x2E1B2138U, 0x4D2C6DFCU, 0x53380D13U,
    0x650A7354U, 0x766A0ABBU, 0x81C2C92EU, 0x92722C85U,
    0xA2BFE8A1U, 0xA81A664BU, 0xC24B8B70U, 0xC76C51A3U,
    0xD192E819U, 0xD6990624U, 0xF40E3585U, 0x106AA070U,
    0x19A4C116U, 0x1E376C08U, 0x2748774CU, 0x34B0BCB5U,
    0x391C0CB3U, 0x4ED8AA4AU, 0x5B9CCA4FU, 0x682E6FF3U,
    0x748F82EEU, 0x78A5636FU, 0x84C87814U, 0x8CC70208U,
    0x90BEFFFAU, 0xA4506CEBU, 0xBEF9A3F7U, 0xC67178F2U
};

static uint32_t rotr32(uint32_t value, unsigned int bits) {
    return (value >> bits) | (value << (32U - bits));
}

static uint32_t loadBigEndian32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24)
        | ((uint32_t)bytes[1] << 16)
        | ((uint32_t)bytes[2] << 8)
        | (uint32_t)bytes[3];
}

static void compressBlock(uint32_t state[8], const uint8_t block[64]) {
    uint32_t schedule[64];
    for (int index = 0; index < 16; index++) {
        schedule[index] = loadBigEndian32(block + index * 4);
    }
    for (int index = 16; index < 64; index++) {
        uint32_t s0 = rotr32(schedule[index - 15], 7) ^ rotr32(schedule[index - 15], 18)
            ^ (schedule[index - 15] >> 3);
        uint32_t s1 = rotr32(schedule[index - 2], 17) ^ rotr32(schedule[index - 2], 19)
            ^ (schedule[index - 2] >> 10);
        schedule[index] = schedule[index - 16] + s0 + schedule[index - 7] + s1;
    }

    uint32_t a = state[0];
    uint32_t b = state[1];
    uint32_t c = state[2];
    uint32_t d = state[3];
    uint32_t e = state[4];
    uint32_t f = state[5];
    uint32_t g = state[6];
    uint32_t h = state[7];

    for (int index = 0; index < 64; index++) {
        uint32_t bigS1 = rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25);
        uint32_t choose = (e & f) ^ (~e & g);
        uint32_t temp1 = h + bigS1 + choose + kSwiftKSHA256K[index] + schedule[index];
        uint32_t bigS0 = rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22);
        uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = bigS0 + majority;

        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
}

void kswiftk_sha256(const uint8_t *data, size_t length, uint8_t digest[32]) {
    uint32_t state[8] = {
        0x6A09E667U, 0xBB67AE85U, 0x3C6EF372U, 0xA54FF53AU,
        0x510E527FU, 0x9B05688CU, 0x1F83D9ABU, 0x5BE0CD19U
    };

    size_t offset = 0;
    while (length - offset >= 64) {
        compressBlock(state, data + offset);
        offset += 64;
    }

    uint8_t tail[128];
    memset(tail, 0, sizeof(tail));
    size_t remaining = length - offset;
    if (remaining > 0) {
        memcpy(tail, data + offset, remaining);
    }
    tail[remaining] = 0x80U;
    size_t paddedBlocks = remaining < 56 ? 1 : 2;
    uint64_t bitLength = (uint64_t)length * 8U;
    for (int index = 0; index < 8; index++) {
        tail[paddedBlocks * 64 - 1 - index] = (uint8_t)(bitLength >> (8 * index));
    }
    compressBlock(state, tail);
    if (paddedBlocks == 2) {
        compressBlock(state, tail + 64);
    }

    for (int index = 0; index < 8; index++) {
        digest[index * 4] = (uint8_t)(state[index] >> 24);
        digest[index * 4 + 1] = (uint8_t)(state[index] >> 16);
        digest[index * 4 + 2] = (uint8_t)(state[index] >> 8);
        digest[index * 4 + 3] = (uint8_t)state[index];
    }
}
