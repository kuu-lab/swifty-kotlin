import kotlin.coroutines.*
interface Value { suspend fun result(n: Int = 21): Int }
class Impl: Value { override suspend fun result(n: Int): Int = n * 2 }
suspend fun suspended(a: Int = 20, b: Int = a + 2): Int = suspendCoroutine<Int> { it.resume(a + b) }
suspend fun Int.add(n: Int = 2): Int = suspended(a = this, b = n)
suspend fun main() {
    println(suspended()); println(suspended(b = 22)); println(40.add())
    val v: Value = Impl(); println(v.result())
}
