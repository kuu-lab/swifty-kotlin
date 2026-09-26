#ifndef KSWIFTK_RUNTIME_C_ATOMICS_H
#define KSWIFTK_RUNTIME_C_ATOMICS_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

// Hardware atomic ops backing kotlin.concurrent.Atomic* boxes. Kotlin atomics
// carry sequential-consistency visibility guarantees, so every op uses
// memory_order_seq_cst — matching the full-barrier semantics the previous
// NSLock-backed storage provided.
//
// Signatures use plain pointer types because Swift cannot import _Atomic
// types; the atomic qualifier is applied inside each function, so all accesses
// through these helpers are atomic while Swift sees UnsafeMutablePointer.
// All functions are `static inline`: callers' object files carry the code, so
// produced binaries need no extra objects beyond the Runtime target's own.

#define KKRT_ATOMIC_OPS(SUFFIX, T)                                                \
    static inline T kkrt_atomic_##SUFFIX##_load(const T *cell) {                  \
        return atomic_load_explicit((const _Atomic T *)cell,                      \
                                    memory_order_seq_cst);                        \
    }                                                                            \
    static inline void kkrt_atomic_##SUFFIX##_store(T *cell, T desired) {         \
        atomic_store_explicit((_Atomic T *)cell, desired, memory_order_seq_cst);  \
    }                                                                            \
    static inline T kkrt_atomic_##SUFFIX##_exchange(T *cell, T desired) {         \
        return atomic_exchange_explicit((_Atomic T *)cell, desired,               \
                                        memory_order_seq_cst);                    \
    }                                                                            \
    /* Returns the cell's observed content (the prior value on success, the      \
     * actual value on failure) and reports whether the exchange happened. */    \
    static inline T kkrt_atomic_##SUFFIX##_compare_exchange(                      \
        T *cell, T expected, T desired, bool *exchanged) {                        \
        T exp = expected;                                                         \
        *exchanged = atomic_compare_exchange_strong_explicit(                     \
            (_Atomic T *)cell, &exp, desired, memory_order_seq_cst,               \
            memory_order_seq_cst);                                                 \
        return exp;                                                               \
    }                                                                            \
    static inline T kkrt_atomic_##SUFFIX##_fetch_add(T *cell, T delta) {          \
        return atomic_fetch_add_explicit((_Atomic T *)cell, delta,                \
                                         memory_order_seq_cst);                   \
    }

KKRT_ATOMIC_OPS(i32, int32_t)
KKRT_ATOMIC_OPS(word, intptr_t)

#endif
