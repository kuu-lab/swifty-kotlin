// BUG-258: a relational comparison between a floating-point and an integer
// operand must widen the integer side to the floating-point value it
// represents before comparing -- kk_op_d*/kk_op_f* interpret both arguments
// as raw IEEE-754 bit patterns, so an un-widened Int/Long operand's bit
// pattern was misread as an unrelated (near-zero denormal) double/float
// value instead of the numeric value it holds.
fun main() {
    val v = 0.6
    println(v > 0)
    println(v <= 1)
    println(v < 1)
    println(v >= 0)
    println(1 >= v)
    println(0 < v)
    println(2 > 1.5)
    println(1L <= 0.6)
    println(1.5f <= 2.0)
    println(3.0f > 2)
}
