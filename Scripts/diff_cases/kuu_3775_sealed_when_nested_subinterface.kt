// KUU-3775: covering every grandchild of a nested sealed child counts as
// covering that child when checking `when` exhaustiveness.
sealed interface F
sealed interface N : F
class A : N
class B : N
class C : F

fun s(f: F): String = when (f) {
    is A -> "a"
    is B -> "b"
    is C -> "c"
}

// A nested sealed child covered directly by `is N` still works.
fun n(f: F): String = when (f) {
    is N -> "n"
    is C -> "c"
}

// Exhaustiveness propagates through more than one sealed level.
sealed interface R
sealed interface Mid : R
sealed interface Leaf : Mid
class X : Leaf
class Y : Leaf
class Z : Mid
class W : R

fun r(v: R): String = when (v) {
    is X -> "x"
    is Y -> "y"
    is Z -> "z"
    is W -> "w"
}

// An enum subtype nested under a sealed child is exhausted by its entries.
sealed interface G
sealed interface GN : G
enum class E : GN { P, Q }
class GA : GN
class GC : G

fun g(v: G): String = when (v) {
    E.P -> "p"
    E.Q -> "q"
    is GA -> "ga"
    is GC -> "gc"
}

// Sealed classes (not just interfaces) propagate the same way.
sealed class SF
sealed class SN : SF()
class SA : SN()
class SB : SN()
class SC : SF()

fun sf(v: SF): String = when (v) {
    is SA -> "sa"
    is SB -> "sb"
    is SC -> "sc"
}

fun main() {
    println(s(A()))
    println(s(B()))
    println(s(C()))
    println(n(A()))
    println(n(C()))
    println(r(X()))
    println(r(Y()))
    println(r(Z()))
    println(r(W()))
    println(g(E.P))
    println(g(E.Q))
    println(g(GA()))
    println(g(GC()))
    println(sf(SA()))
    println(sf(SB()))
    println(sf(SC()))
}
