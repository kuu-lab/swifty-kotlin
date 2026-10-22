// WITH_STDLIB
// KUU-2800: postfix `!!` and infix `!is` after a trailing-lambda call must
// continue the enclosing expression. Previously the expression stopped at the
// lambda's `}`, the leftover operator became a top-level statement, and the
// file flipped into script mode (synthesized `main` -> SEMA-0001, and lost
// extension-receiver `this` -> SEMA-0051).
val List<Int>.cn get() = this.minBy { it.toString() }!!
fun List<Int>.cnFun() = this.maxBy { it.toString() }!!
val List<Int>.cnOrNull get() = this.minByOrNull { it.toString() }!!

fun notNullAfterLambda(c: String) = c.let { it.toIntOrNull() }!!
fun notIsAfterLambda(c: Any) = c.let { it } !is Int
fun notInAfterLambda(c: String, x: Set<Int>) = c.let { it.toInt() } !in x

fun main() {
    println(listOf(1).cn)
    println(listOf(2).cnFun())
    println(listOf(3).cnOrNull)
    println(notNullAfterLambda("7"))
    println(notIsAfterLambda("x"))
    println(notIsAfterLambda(1))
    println(notInAfterLambda("5", setOf(1, 2)))
}
