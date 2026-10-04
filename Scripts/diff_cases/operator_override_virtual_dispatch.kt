// Operator calls (binary operators, comparisons, ==, in, destructuring) on an
// open/abstract member operator must dispatch on the receiver's runtime type,
// and an override inherits the `operator` modifier without repeating it.

abstract class Shape { abstract operator fun plus(n: Int): Int }
class Sq(val s: Int) : Shape() { override operator fun plus(n: Int) = s * s + n }
class Tri(val s: Int) : Shape() { override operator fun plus(n: Int) = s * 3 + n }

open class Cmp(val v: Int) : Comparable<Cmp> { override fun compareTo(other: Cmp): Int = v - other.v }
class RevCmp(v: Int) : Cmp(v) { override fun compareTo(other: Cmp): Int = other.v - v }

open class Eq(val v: Int) {
    override fun equals(other: Any?) = other is Eq && other.v == v
    override fun hashCode() = v
}
class AlwaysEq(v: Int) : Eq(v) {
    override fun equals(other: Any?) = true
    override fun hashCode() = 0
}

open class Bag { open operator fun contains(x: Int): Boolean = false }
class EvenBag : Bag() { override fun contains(x: Int): Boolean = x % 2 == 0 }

open class Adder { open operator fun plus(n: Int) = n }
open class Doubler : Adder() { override fun plus(n: Int) = n * 2 }
class Tripler : Doubler() { override fun plus(n: Int) = n * 3 }

open class P(val a: Int, val b: Int) {
    open operator fun component1() = a
    open operator fun component2() = b
}
class Q(a: Int, b: Int) : P(a, b) {
    override fun component1() = a * 10
    override fun component2() = b * 10
}

fun main() {
    val shapes: List<Shape> = listOf(Sq(2), Tri(2))
    for (s in shapes) println(s + 1)

    val x: Cmp = RevCmp(1)
    println(x < Cmp(2))
    println(x > Cmp(2))
    println(RevCmp(1) < Cmp(2))

    val e: Eq = AlwaysEq(1)
    println(e == Eq(2))
    println(e != Eq(2))
    println(Eq(1) == Eq(2))

    val b = EvenBag()
    println(4 in b)
    println(3 !in b)
    val c: Bag = EvenBag()
    println(4 in c)
    println(3 in c)
    println(4 in Bag())

    println(Doubler() + 1)
    println(Tripler() + 1)
    val adder: Adder = Tripler()
    println(adder + 2)

    val p: P = Q(1, 2)
    val (px, py) = p
    println("$px $py")
    val ps: List<P> = listOf(P(1, 2), Q(3, 4))
    for ((u, v) in ps) println("$u $v")
}
