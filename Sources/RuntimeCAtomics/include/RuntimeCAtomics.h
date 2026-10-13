#ifndef KSWIFTK_RUNTIME_C_ATOMICS_H
#define KSWIFTK_RUNTIME_C_ATOMICS_H

#if defined(__linux__) && !defined(_GNU_SOURCE)
// pthread_getattr_np / pthread_attr_getstack are GNU extensions.
#define _GNU_SOURCE
#endif

#include <pthread.h>
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

// Lowest usable address of the calling thread's stack, or 0 when the
// platform cannot report it. Backs `kk_stack_overflow_check` (KUU-1384):
// generated function prologues compare a marker inside their own frame
// against this bound plus a reserve so deep recursion raises a catchable
// StackOverflowError instead of faulting past the guard page.
static inline uintptr_t kkrt_thread_stack_low_address(uintptr_t *outSize) {
#if defined(__APPLE__)
    void *top = pthread_get_stackaddr_np(pthread_self());
    size_t size = pthread_get_stacksize_np(pthread_self());
    if (top == NULL || size == 0) {
        return 0;
    }
    if (outSize != NULL) {
        *outSize = (uintptr_t)size;
    }
    return (uintptr_t)top - (uintptr_t)size;
#elif defined(__linux__)
    pthread_attr_t attr;
    if (pthread_getattr_np(pthread_self(), &attr) != 0) {
        return 0;
    }
    void *addr = NULL;
    size_t size = 0;
    int rc = pthread_attr_getstack(&attr, &addr, &size);
    pthread_attr_destroy(&attr);
    if (rc != 0 || addr == NULL || size == 0) {
        return 0;
    }
    if (outSize != NULL) {
        *outSize = (uintptr_t)size;
    }
    return (uintptr_t)addr;
#else
    (void)outSize;
    return 0;
#endif
}

#endif
