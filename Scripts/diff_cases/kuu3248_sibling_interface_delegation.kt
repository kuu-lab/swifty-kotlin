// KUU-3248: a `by`-delegated implementation satisfies abstract members with a
// matching signature on sibling interfaces, not just on the delegated
// interface's own closure.
interface A { fun foo(): Int }
interface B { fun foo(): Int }
interface C { fun foo(): Int }
class Z(private val a: A) : A by a, B, C
class Impl : A { override fun foo(): Int = 1 }

interface CovA { fun cov(): Int }
interface CovB { fun cov(): Number }
class CovZ(private val a: CovA) : CovA by a, CovB
class CovImpl : CovA { override fun cov(): Int = 2 }

interface PropA { val prop: Int }
interface PropB { val prop: Int }
class PropZ(private val a: PropA) : PropA by a, PropB
class PropImpl : PropA { override val prop: Int = 3 }

interface GenA<T> { fun pick(t: T): Int }
interface GenB { fun pick(t: String): Int }
class GenZ(private val a: GenA<String>) : GenA<String> by a, GenB
class GenImpl : GenA<String> { override fun pick(t: String): Int = 4 }

fun main() {
    println(Z(Impl()).foo())
    println(CovZ(CovImpl()).cov())
    println(PropZ(PropImpl()).prop)
    println(GenZ(GenImpl()).pick("x"))
    val literal = object : A by Impl(), B {}
    println(literal.foo())
}
