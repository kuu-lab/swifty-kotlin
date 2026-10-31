// KUU-3795: a call-result infix receiver (`f() op operand`) must not
// swallow the following statement. The pending-infix parity count treated
// `f` and `()` as two elements, so a complete `f() op x` line looked like
// it ended in a dangling infix name and merged the next statement away.
class B {
    private fun rootSize() = 4
    fun g(): Int {
        val leafCount = rootSize() shr 1
        val leafBufferIterator = leafBufferIterator(leafCount)
        return leafBufferIterator
    }
    private fun leafBufferIterator(index: Int): Int = index
}

fun main() {
    println(B().g())
    // A parenthesized infix operand stays in the operand slot.
    val complete = 1 or (2)
    println(complete)
    // `!!` is postfix on its operand, not an alternation element.
    val n: Int? = 5
    val m = n!! or 2
    println(m)
    // A call expression as the infix operand.
    val t = 2 or triple(1)
    println(t)
}

fun triple(i: Int) = i * 3
