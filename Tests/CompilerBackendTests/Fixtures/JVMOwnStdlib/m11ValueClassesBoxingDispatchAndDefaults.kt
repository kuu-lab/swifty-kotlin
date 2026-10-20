var creations = 0
interface Measure { fun add(other: Meter): Meter }
@JvmInline value class Meter(val value: Int): Measure {
    init { creations += 1 }
    override fun add(other: Meter): Meter = Meter(value + other.value)
    fun step(n: Int = 1): Meter = Meter(value + n)
}
class Box(val meter: Meter)
fun twice(m: Meter = Meter(5)): Meter = Meter(m.value * 2)
fun identity(m: Meter?): Meter? = m
fun <T> same(value: T): T = value
fun main() {
    val m = Meter(20)
    val boxed: Any = m
    println(creations); println(boxed); println(creations)
    val list = listOf(m); println(list[0].value); println(same(m).value)
    println(twice(m)); println(twice()); println(m.step()); println(m.step(3))
    val target: Measure = m
    println(target.add(Meter(2))); println(Box(m).meter.value)
    println(identity(null)); println(identity(m)); println(m == Meter(20)); println(m.hashCode())
    val capture = { m.value }; println(capture())
    val holder = object { fun read(): Int = m.value }; println(holder.read())
}
