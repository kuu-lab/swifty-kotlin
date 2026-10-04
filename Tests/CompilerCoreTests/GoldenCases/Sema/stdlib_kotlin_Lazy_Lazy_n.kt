package golden.sema

fun readLazy(lazy: Lazy<Int>): Int {
    if (lazy.isInitialized()) {
        return lazy.value
    }
    return 0
}

fun main() {
    println(readLazy(lazyOf(42)))
}
