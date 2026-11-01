// KUU-3938: an infix initializer whose receiver is a call result and
// whose operand is a top-level val (`g() shr LOG2`) must not swallow the
// next local val declaration. The pending-infix parity count used to
// treat `g` and `()` as separate alternation elements, so the complete
// line looked like a dangling infix call and `val b` was folded into the
// same statement group and dropped — `return a + b` then reported
// unresolved `b` (KSWIFTK-SEMA-0022) with a broken `a` (KSWIFTK-SEMA-0002).
// Converged with KUU-3794/KUU-3795 (#12226/#12230), which fixed the same
// operand/name parity for call-result receivers.
val LOG2 = 5
fun h(): Int = 32
fun g(): Int {
    val a = h() shr LOG2
    val b = 42
    return a + b
}

const val LOGC = 4
fun k(): Int {
    val a = h() shr LOGC
    val b = 42
    return a + b
}

fun main() {
    println(g())
    println(k())
}
