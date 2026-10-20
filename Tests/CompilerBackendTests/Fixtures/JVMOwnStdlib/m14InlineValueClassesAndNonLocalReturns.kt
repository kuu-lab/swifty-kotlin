@JvmInline value class V(val value: Int) {
    inline fun apply(other: V, block: (V) -> V): V = block(other)
}
@JvmInline value class Wide(val value: Long)
@JvmInline value class Box<T>(val value: T)
inline fun transform(v: V = V(21), block: (V) -> V = { it }): V = block(v)
inline fun V.plus(other: V = V(1)): V = V(value + other.value)
inline fun <T> identity(v: Box<T>): Box<T> = v
inline fun wide(v: Wide, block: (Wide) -> Wide): Wide = block(v)
inline fun guarded(v: V, block: (V) -> V): V {
    try { return block(v) } finally { println("finally") }
}
fun early(): V { guarded(V(7)) { return it }; return V(0) }
fun main() {
    println(transform()); println(transform(V(20)) { it.plus(V(2)) })
    println(V(1).apply(V(42)) { it }); println(identity(Box("generic")))
    println(wide(Wide(20L)) { Wide(it.value + 2L) }); println(early())
}
