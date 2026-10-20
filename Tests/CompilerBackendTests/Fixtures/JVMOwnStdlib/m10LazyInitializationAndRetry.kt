var calls = 0
val top: Int by lazy { calls += 1; 10 }
class Box(val seed: Int) { val value: Int by lazy { calls += 1; seed * 2 } }
fun main() {
    println(calls); println(top); println(top); println(calls)
    val first = Box(5); val second = Box(7)
    println(first.value); println(first.value); println(second.value); println(calls)
    var attempts = 0
    val retry by lazy(LazyThreadSafetyMode.NONE) { attempts += 1; if (attempts == 1) throw IllegalStateException("retry"); 42 }
    try { println(retry) } catch (e: IllegalStateException) { println(e.message) }
    println(retry); println(retry); println(attempts)
    val nullable: String? by lazy(LazyThreadSafetyMode.PUBLICATION) { calls += 1; null }
    println(nullable); println(nullable); println(calls)
    val state = lazy(lock = null) { 8 }
    println(state.isInitialized()); println(state.value); println(state.isInitialized())
}
