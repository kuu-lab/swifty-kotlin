// KUU-1254: synthesized value-class rendering must retain nominal identity.
@JvmInline value class VC(val v: Int)
@JvmInline value class VC2(val v: Int) { override fun toString() = "custom$v" }
@JvmInline value class WS(val s: String)
@JvmInline value class Meters(val v: Double)
@JvmInline value class Maybe(val v: Int?)
class Outer {
    @JvmInline value class Nested(val n: Int)
}
data class Holder(val value: VC)
fun main() {
    println(VC(5))
    println(VC(5).toString())
    println(VC2(5))
    println(WS("abc"))
    println(listOf(VC(1), VC(2)))
    println("template=${VC(6)}")
    val erased: Any = VC(7)
    println(erased.toString())
    println("$erased")
    println(Meters(1.5))
    println(Maybe(null))
    println(Maybe(9))
    println(Outer.Nested(8))
    println(Holder(VC(10)))
    println(VC(5) == VC(5))
    println(VC(5).hashCode())
}
