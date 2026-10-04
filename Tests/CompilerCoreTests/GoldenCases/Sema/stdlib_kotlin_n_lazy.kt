package golden.sema

fun useLazyFactory(): Lazy<Int> = lazy { 1 }

fun useLazyWithLock(): Lazy<String> = lazy(null) { "locked" }

fun useLazyWithMode(): Lazy<Int> = lazy(LazyThreadSafetyMode.NONE) { 2 }

fun useLazyOf(): Lazy<Int> = lazyOf(3)
