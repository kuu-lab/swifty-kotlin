// WITH_STDLIB
// KUU-2459: preserve membership operators after calls with trailing lambdas.
fun isImportedByDefault(c: String?, x: Set<Int>) = c?.let { it.toInt() } in x

fun box(): String = "OK"

fun minimal(c: String, x: Set<Int>) = c.let { it.toInt() } in x
fun negated(c: String, x: Set<Int>) = c.let { it.toInt() } !in x
fun safeNegated(c: String?, x: Set<Int>) = c?.let { it.toInt() } !in x
fun parenthesized(c: String, x: Set<Int>) = (c.let { it.toInt() }) in x
fun plusAfter(c: String) = c.let { it.toInt() } + 1
fun trailingLambdaOnly(c: String) = c.let { it.toInt() }

fun main() {
    println(box())
    println(isImportedByDefault("1", setOf(1)))
    println(minimal("1", setOf(1)))
    println(negated("1", setOf(1)))
    println(safeNegated("1", setOf(1)))
    println(parenthesized("1", setOf(1)))
    println(plusAfter("1"))
    println(trailingLambdaOnly("1"))
    println(1 in setOf(1))
}
