class Value<T>(val item: @UnsafeVariance T)
fun choose(flag: Boolean): Int = if (flag) @Suppress("UNUSED") { 3 } else @Suppress("UNUSED") { 4 }
fun choosePlain(flag: Boolean): Int = if (flag) { 3 } else { 4 }
fun unary(): Int = @kotlin.Suppress("UNUSED") -7 + 9
fun failure(): Int = @Suppress("UNUSED") throw IllegalArgumentException("annotated")
fun main() {
    println(choose(true)); println(choose(false))
    println(choosePlain(true)); println(choosePlain(false))
    println(unary())
    var value = 1
    println(++@Suppress("UNUSED") value)
    println(@Suppress("UNUSED") ++value)
    println(-@Suppress("UNUSED") value)
    @Suppress("UNUSED") val local = Value("type")
    println(local.item)
    val obj = object { @Suppress("UNUSED") val item: Int = 5 }
    println(obj.item)
    try { failure() } catch (e: IllegalArgumentException) { println(e.message) }
}
