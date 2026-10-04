// Subject-less `when` exhaustiveness only applies when the `when` is used
// as an expression (its value is required). Used as a statement, the value
// is discarded and Kotlin does not require an `else` branch.

// OK: statement position, value discarded - no diagnostic expected.
fun statementPositionNoElse(x: Int): Int {
    val result = 0
    when {
        x > 10 -> result
        x > 0 -> result
    }
    return result
}

// ERROR: expression position (returned value) - exhaustiveness still required.
fun expressionPositionNoElse(x: Int): Int {
    return when {
        x > 10 -> 1
        x > 0 -> 2
    }  // KSWIFTK-SEMA-0004: Non-exhaustive when expression.
}
