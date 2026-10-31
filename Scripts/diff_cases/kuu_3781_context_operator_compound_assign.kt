// Regression (KUU-3781): a `context(...)` operator overload pair must
// dispatch plusAssign through the implicit context receiver supplied by
// `with`. Mirrors the JetBrains contextParameters/
// compoundAssignmentOperators.kt case that SIGSEGV'd at runtime on the
// ticket's baseline.

data class Result(var i: Int)

var operationScore = 0

context(score: Int)
operator fun Result.plus(other: Result): Result {
    operationScore += score
    return Result(i + other.i)
}

context(score: Int)
operator fun Result.plusAssign(other: Result) {
    operationScore += score
    i += other.i
}

fun main() {
    val result = Result(0)
    with(1) {
        result += (Result(1) + Result(1))
        result += Result(1)
    }
    println(if (result.i == 3 && operationScore == 3) "OK" else "fail ${result.i} $operationScore")
}
