// KUU-2299: expected result types reach nested lambdas through overloaded generic calls.
// The first case reproduces JetBrains Kotlin's lambdaAsLastExpressionInLambda.kt.
val foo: ((String) -> String) = run {
    { it }
}

fun box() = foo("OK")

fun <R> generic(block: () -> R): R = block()
fun <T, R> T.generic(block: T.() -> R): R = block()

val overloadedFoo: ((String) -> String) = generic { { it } }

fun overloadedBox(): String = overloadedFoo("OK")

fun main() {
    println(box())
    println(overloadedBox())
}
