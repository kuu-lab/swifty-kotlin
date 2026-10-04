fun main() {
    val a: Lazy<Int> = lazyOf(1)
    println(a.value)

    val b: Lazy<Int> = lazy { 2 }
    println(b.value)

    val c: Lazy<Int> = lazy(LazyThreadSafetyMode.NONE) { 3 }
    println(c.value)
}
