package golden.sema

fun useLazyValue(): Int {
    val l = lazyOf(42)
    return l.value
}

fun useLazyIsInitialized(): Boolean {
    val l = lazyOf(42)
    return l.isInitialized()
}

fun useLazyBy(): Int {
    val x by lazy { 42 }
    return x
}
