// Exact decimal-string-to-IEEE-754 conversion used by the WebAssembly backend.
//
// This C source is the reference implementation for
// Sources/CompilerBackend/Wasm/WasmDecimalParserBody.swift.  It is compiled
// to a single self-contained wasm function by Scripts/generate_wasm_decimal_parser.sh.
// The generated function deliberately does not use libc, imports, globals, or
// calls; all big-integer scratch storage is supplied by the caller.
//
// parse_exact_fp(data, length, scratch, isFloat) -> IEEE bits, or UINT64_MAX
// when the input is not a decimal floating-point literal.  The scratch layout is:
//   [length bytes digit copy][8-byte alignment padding]
//   [9 arrays of (length + 1024) u32 big-integer limbs][64 bytes slack]
// The wasm wrapper allocates exactly that many bytes.  The conversion itself is
// exact: it forms the input rational with large integers, extracts the target
// precision by integer division, and rounds the remainder ties-to-even.

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint32_t *w;
    uint32_t n;
    uint32_t cap;
} Big;

static inline __attribute__((always_inline)) void bn_init(Big *b, uint32_t *w, uint32_t cap) {
    b->w = w;
    b->cap = cap;
    b->n = 0;
}

static inline __attribute__((always_inline)) void bn_zero(Big *b) {
    for (uint32_t i = 0; i < b->cap; i++) b->w[i] = 0;
    b->n = 0;
}

static inline __attribute__((always_inline)) void bn_trim(Big *b) {
    while (b->n > 0 && b->w[b->n - 1] == 0) b->n--;
}

static inline __attribute__((always_inline)) void bn_set_u64(Big *b, uint64_t v) {
    bn_zero(b);
    b->w[0] = (uint32_t)v;
    b->w[1] = (uint32_t)(v >> 32);
    b->n = 2;
    bn_trim(b);
}

static inline __attribute__((always_inline)) void bn_copy(Big *d, const Big *s) {
    for (uint32_t i = 0; i < s->n; i++) d->w[i] = s->w[i];
    for (uint32_t i = s->n; i < d->cap; i++) d->w[i] = 0;
    d->n = s->n;
}

static inline __attribute__((always_inline)) int bn_cmp(const Big *a, const Big *b) {
    uint32_t an = a->n, bn = b->n;
    while (an > 0 && a->w[an - 1] == 0) an--;
    while (bn > 0 && b->w[bn - 1] == 0) bn--;
    if (an < bn) return -1;
    if (an > bn) return 1;
    for (uint32_t i = an; i-- > 0;) {
        if (a->w[i] < b->w[i]) return -1;
        if (a->w[i] > b->w[i]) return 1;
    }
    return 0;
}

static inline __attribute__((always_inline)) void bn_add_small(Big *b, uint32_t x) {
    uint64_t carry = x;
    uint32_t i = 0;
    while (carry && i < b->cap) {
        uint64_t t = (uint64_t)b->w[i] + carry;
        b->w[i] = (uint32_t)t;
        carry = t >> 32;
        i++;
    }
    if (i > b->n) b->n = i;
}

static inline __attribute__((always_inline)) void bn_mul_small(Big *b, uint32_t m) {
    uint64_t carry = 0;
    for (uint32_t i = 0; i < b->n; i++) {
        uint64_t t = (uint64_t)b->w[i] * m + carry;
        b->w[i] = (uint32_t)t;
        carry = t >> 32;
    }
    if (carry) {
        b->w[b->n++] = (uint32_t)carry;
    }
}

static inline __attribute__((always_inline)) uint32_t bn_bits(const Big *b) {
    if (b->n == 0) return 0;
    uint32_t top = b->w[b->n - 1];
    uint32_t bits = (b->n - 1) * 32;
    while (top) {
        bits++;
        top >>= 1;
    }
    return bits;
}

static inline __attribute__((always_inline)) int bn_bit(const Big *b, uint32_t bit) {
    uint32_t limb = bit >> 5;
    if (limb >= b->n) return 0;
    return (int)((b->w[limb] >> (bit & 31)) & 1u);
}

static inline __attribute__((always_inline)) void bn_copy_shift(Big *d, const Big *s, uint32_t bits) {
    bn_zero(d);
    uint32_t limbs = bits >> 5;
    uint32_t sh = bits & 31;
    if (sh == 0) {
        for (uint32_t i = 0; i < s->n; i++) d->w[i + limbs] = s->w[i];
        d->n = s->n + limbs;
    } else {
        uint32_t carry = 0;
        for (uint32_t i = 0; i < s->n; i++) {
            uint32_t v = s->w[i];
            d->w[i + limbs] = (v << sh) | carry;
            carry = v >> (32 - sh);
        }
        d->n = s->n + limbs;
        if (carry) d->w[d->n++] = carry;
    }
    bn_trim(d);
}

static inline __attribute__((always_inline)) void bn_shl1(Big *b) {
    uint32_t carry = 0;
    for (uint32_t i = 0; i < b->n; i++) {
        uint32_t next = b->w[i] >> 31;
        b->w[i] = (b->w[i] << 1) | carry;
        carry = next;
    }
    if (carry) b->w[b->n++] = carry;
    if (b->n == 0) b->n = 1;
}

static inline __attribute__((always_inline)) void bn_sub(Big *a, const Big *b) {
    uint32_t borrow = 0;
    for (uint32_t i = 0; i < a->n; i++) {
        uint32_t av = a->w[i];
        uint32_t bv = i < b->n ? b->w[i] : 0;
        uint32_t sub = bv + borrow;
        uint32_t out = av - sub;
        borrow = (av < sub) || (borrow && bv == 0xffffffffu);
        a->w[i] = out;
    }
    bn_trim(a);
}

static inline __attribute__((always_inline)) uint64_t bn_divmod_smallq(const Big *num, const Big *den, Big *rem, Big *tmp) {
    bn_zero(rem);
    if (rem->cap) rem->n = 1;
    uint64_t q = 0;
    uint32_t bits = bn_bits(num);
    for (uint32_t pos = bits; pos-- > 0;) {
        bn_shl1(rem);
        if (bn_bit(num, pos)) rem->w[0] |= 1u;
        if (bn_cmp(rem, den) >= 0) {
            bn_sub(rem, den);
            if (pos < 64) q |= 1ull << pos;
            else q = ~0ull;
        }
    }
    (void)tmp;
    return q;
}

#define INVALID_PARSE UINT64_MAX

static inline __attribute__((always_inline)) int is_digit_byte(uint8_t c) {
    return c >= (uint8_t)'0' && c <= (uint8_t)'9';
}

uint64_t parse_exact_fp(uint64_t dataPtr, uint64_t len64, uint64_t scratchPtr, uint64_t isFloat64) {
    #ifdef HOST_TEST
    const uint8_t *data = (const uint8_t *)(uintptr_t)dataPtr;
    uint8_t *scratchBytes = (uint8_t *)(uintptr_t)scratchPtr;
#else
    const uint8_t *data = (const uint8_t *)(uintptr_t)(uint32_t)dataPtr;
    uint8_t *scratchBytes = (uint8_t *)(uintptr_t)(uint32_t)scratchPtr;
#endif
    uint32_t len = (uint32_t)len64;
    if (len == 0) return INVALID_PARSE;

    uint32_t pos = 0;
    int neg = 0;
    int isFloat = (int)isFloat64;
    if (data[pos] == (uint8_t)'+' || data[pos] == (uint8_t)'-') {
        neg = data[pos] == (uint8_t)'-';
        pos++;
    }
    if (pos >= len) return INVALID_PARSE;

    uint8_t *digits = scratchBytes;
    uint32_t totalDigits = 0;
    uint32_t fracDigits = 0;
    int seenDigit = 0;
    while (pos < len && is_digit_byte(data[pos])) {
        digits[totalDigits++] = (uint8_t)(data[pos++] - (uint8_t)'0');
        seenDigit = 1;
    }
    if (pos < len && data[pos] == (uint8_t)'.') {
        pos++;
        while (pos < len && is_digit_byte(data[pos])) {
            digits[totalDigits++] = (uint8_t)(data[pos++] - (uint8_t)'0');
            fracDigits++;
            seenDigit = 1;
        }
    }
    if (!seenDigit) return INVALID_PARSE;

    int64_t expPart = 0;
    if (pos < len && (data[pos] == (uint8_t)'e' || data[pos] == (uint8_t)'E')) {
        pos++;
        int expNeg = 0;
        if (pos < len && (data[pos] == (uint8_t)'+' || data[pos] == (uint8_t)'-')) {
            expNeg = data[pos] == (uint8_t)'-';
            pos++;
        }
        if (pos >= len || !is_digit_byte(data[pos])) return INVALID_PARSE;
        while (pos < len && is_digit_byte(data[pos])) {
            if (expPart < 1000000000) {
                expPart = expPart * 10 + (int64_t)(data[pos] - (uint8_t)'0');
                if (expPart > 1000000000) expPart = 1000000000;
            }
            pos++;
        }
        if (expNeg) expPart = -expPart;
    }
    if (pos != len) return INVALID_PARSE;

    uint32_t leadingZeros = 0;
    while (leadingZeros < totalDigits && digits[leadingZeros] == 0) leadingZeros++;
    uint32_t trailingZeros = 0;
    while (trailingZeros < totalDigits - leadingZeros && digits[totalDigits - 1 - trailingZeros] == 0) trailingZeros++;
    uint32_t ndigits = totalDigits - leadingZeros - trailingZeros;
    uint64_t signBit = neg ? (isFloat ? 0x80000000ull : 0x8000000000000000ull) : 0;
    if (ndigits == 0) return signBit;

    int64_t q = expPart - (int64_t)fracDigits + (int64_t)trailingZeros;
    int64_t decLow = (int64_t)ndigits - 1 + q;
    int64_t decHigh = (int64_t)ndigits + q;
    int32_t maxExp = isFloat ? 127 : 1023;
    int32_t minNormalExp = isFloat ? -126 : -1022;
    int32_t subShift = isFloat ? -149 : -1074;
    int32_t precision = isFloat ? 24 : 53;
    int32_t fractionBits = precision - 1;
    int32_t bias = maxExp;
    uint64_t infBits = ((uint64_t)(2 * bias + 1) << fractionBits);
    if (decLow >= 309) return signBit | infBits;
    if (decHigh <= -324) return signBit;

    uintptr_t bigBaseBytes = ((uintptr_t)len + 7u) & ~(uintptr_t)7u;
    uint32_t *base = (uint32_t *)(void *)(scratchBytes + bigBaseBytes);
    uint32_t cap = len + 1024;
    Big n, a, b, num, den, rem, tmp, twice, cmpcopy;
    bn_init(&n, base + 0 * cap, cap);
    bn_init(&a, base + 1 * cap, cap);
    bn_init(&b, base + 2 * cap, cap);
    bn_init(&num, base + 3 * cap, cap);
    bn_init(&den, base + 4 * cap, cap);
    bn_init(&rem, base + 5 * cap, cap);
    bn_init(&tmp, base + 6 * cap, cap);
    bn_init(&twice, base + 7 * cap, cap);
    bn_init(&cmpcopy, base + 8 * cap, cap);

    bn_zero(&n);
    n.n = 1;
    uint32_t sigStart = leadingZeros;
    uint32_t sigEnd = totalDigits - trailingZeros;
    for (uint32_t i = sigStart; i < sigEnd; i++) {
        bn_mul_small(&n, 10);
        bn_add_small(&n, digits[i]);
    }
    bn_trim(&n);

    bn_copy(&a, &n);
    bn_set_u64(&b, 1);
    if (q >= 0) {
        for (int64_t i = 0; i < q; i++) bn_mul_small(&a, 5);
        if (q > 0) {
            bn_copy_shift(&tmp, &a, (uint32_t)q);
            bn_copy(&a, &tmp);
        }
    } else {
        int64_t qq = -q;
        for (int64_t i = 0; i < qq; i++) bn_mul_small(&b, 5);
        bn_copy_shift(&tmp, &b, (uint32_t)qq);
        bn_copy(&b, &tmp);
    }

    int32_t abits = (int32_t)bn_bits(&a);
    int32_t bbits = (int32_t)bn_bits(&b);
    int32_t e = abits - bbits;
    int cmp;
    if (e >= 0) {
        bn_copy_shift(&cmpcopy, &b, (uint32_t)e);
        cmp = bn_cmp(&a, &cmpcopy);
    } else {
        bn_copy_shift(&cmpcopy, &a, (uint32_t)(-e));
        cmp = bn_cmp(&cmpcopy, &b);
    }
    if (cmp < 0) e--;

    if (e > maxExp) return signBit | infBits;

    int subnormal = e < minNormalExp;
    int32_t s = subnormal ? subShift : e - (precision - 1);
    if (s >= 0) {
        bn_copy(&num, &a);
        bn_copy_shift(&den, &b, (uint32_t)s);
    } else {
        bn_copy_shift(&num, &a, (uint32_t)(-s));
        bn_copy(&den, &b);
    }

    uint64_t quotient = bn_divmod_smallq(&num, &den, &rem, &tmp);
    bn_copy_shift(&twice, &rem, 1);
    int roundCmp = bn_cmp(&twice, &den);
    if (roundCmp > 0 || (roundCmp == 0 && (quotient & 1u))) quotient++;

    uint64_t out;
    if (subnormal) {
        uint64_t minNormalUnits = 1ull << fractionBits;
        if (quotient > minNormalUnits) quotient = minNormalUnits;
        out = quotient;
    } else {
        uint64_t carryLimit = 1ull << precision;
        if (quotient >= carryLimit) {
            quotient >>= 1;
            e++;
        }
        if (e > maxExp) {
            out = infBits;
        } else {
            uint64_t expField = (uint64_t)(e + bias);
            uint64_t significand = quotient - (1ull << fractionBits);
            out = (expField << fractionBits) | significand;
        }
    }
    return signBit | out;
}


