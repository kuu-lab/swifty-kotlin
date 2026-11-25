// Regression: a @JvmInline value class that implements an interface stays
// boxed as a nominal object for polymorphic dispatch. Those boxed instances
// must still get structural equals/hashCode — Coil 3.x's Dimension.Pixels
// behind the Dimension sealed interface exposed == and hashCode falling back
// to reference/identity semantics, which broke Size equality and hashing.
interface Named

@JvmInline
value class Id(val value: Int) : Named

// Coil 3.x coil3.size shape: sealed interface + value class + data class
// holding interface-typed fields.
sealed interface Dimension {
    @JvmInline
    value class Pixels(val px: Int) : Dimension

    data object Undefined : Dimension
}

data class Size(val width: Dimension, val height: Dimension)

fun main() {
    // Equality through the interface type (boxed nominal instances).
    val a: Named = Id(3)
    val b: Named = Id(3)
    println(a == b)
    println(a != Id(4))
    println(a.equals(b))

    // Direct construction equality and hashCode.
    println(Id(3) == Id(3))
    println(Id(3) == Id(4))
    println(a.hashCode())
    println(Id(3).hashCode())

    // Data class holding interface-typed value-class fields (Coil Size).
    val s1 = Size(Dimension.Pixels(3), Dimension.Pixels(4))
    val s2 = Size(Dimension.Pixels(3), Dimension.Pixels(4))
    println(s1 == s2)
    println(s1 != Size(Dimension.Pixels(3), Dimension.Pixels(5)))
    println(s1.hashCode() == s2.hashCode())
    println(s1.hashCode())
    println(Size(Dimension.Undefined, Dimension.Undefined) == Size(Dimension.Undefined, Dimension.Undefined))
}
