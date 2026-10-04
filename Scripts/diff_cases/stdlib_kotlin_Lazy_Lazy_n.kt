fun main() {
    val lazy: Lazy<Int> = lazyOf(42)
    println(lazy.isInitialized())
    println(lazy.value)
}
