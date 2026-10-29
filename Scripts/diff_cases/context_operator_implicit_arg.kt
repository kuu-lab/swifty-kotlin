// Regression: binary operator lowering never inserted implicit context
// arguments, crashing or misreading them at run time (KUU-3170,
// compoundAssignmentOperators / unaryOperators).
data class Result(val i: Int)

var operationScore = 0

context(multiplier: Int)
operator fun Result.plus(other: Result): Result {
    operationScore += multiplier
    return Result(i + other.i)
}

context(multiplier: Int)
operator fun Result.inc(): Result {
    operationScore += multiplier
    return Result(i + 1)
}

fun main() {
    var result = Result(0)
    with(2) {
        result++
        result = result + Result(10)
    }
    println("${result.i} ${operationScore}")
}
