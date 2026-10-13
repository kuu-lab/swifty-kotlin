// KUU-1905: A Boolean-returning callable reference adapts to apply's Unit block.
fun main() {
    val referenceValues = mutableListOf<String>()
    val referenceTree = "oak".apply(referenceValues::add)

    val lambdaValues = mutableListOf<String>()
    val lambdaTree = "oak".apply { lambdaValues.add(this) }

    println(referenceTree)
    println(referenceValues)
    println(lambdaTree)
    println(lambdaValues)
}
