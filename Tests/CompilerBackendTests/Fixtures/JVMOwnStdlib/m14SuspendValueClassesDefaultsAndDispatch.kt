@JvmInline value class V(val value: Int)
@JvmInline value class Wide(val value: Long)
interface Source { suspend fun get(v: V): V }
open class Base: Source { override suspend fun get(v: V): V = V(v.value + 1) }
class Child: Base() { override suspend fun get(v: V): V { val x = super.get(v); return V(x.value + 1) } }
suspend fun echo(v: V = V(21)): V = v
suspend fun optional(v: V? = null): V? = v
suspend fun V.plus(other: V = V(1)): V = V(value + other.value)
suspend fun wide(v: Wide): Wide = v
suspend fun number(v: Int): Int = v
suspend fun main() {
    println(echo()); println(optional()); println(optional(V(7))); println(V(20).plus())
    val source: Source = Child(); println(source.get(V(40)))
    val callback: suspend () -> V = { echo(V(42)) }; println(callback())
    println(wide(Wide(9L)))
    val ref: suspend (V) -> V = ::echo; println(ref(V(9)))
    val plain: suspend (Int) -> Int = ::number; println(plain(10))
    println(V(number(11)))
}
