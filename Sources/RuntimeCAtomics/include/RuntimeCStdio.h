#ifndef KSWIFTK_RUNTIME_C_STDIO_H
#define KSWIFTK_RUNTIME_C_STDIO_H

#include <stdio.h>

// Keep the same stdio buffer used by Swift.readLine(). Access through C avoids
// importing libc's mutable stdin global into Swift's concurrency checker.
static inline FILE *kkrt_standard_input(void) {
    return stdin;
}

#endif
