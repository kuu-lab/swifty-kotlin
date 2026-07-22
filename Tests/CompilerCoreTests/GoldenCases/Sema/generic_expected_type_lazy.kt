fun testLazyOf() {
    val x: Lazy<Int> = lazyOf(1)
    println(x.value)
}

fun testLazyLambda() {
    val x: Lazy<Int> = lazy { 1 }
    println(x.value)
}
