package golden.diagnostics

fun longRangeFromIntLiteral(): LongRange = 1..10

fun uintRangeFromIntLiteral(): UIntRange = 1..10

fun charRangeFromIntLiteral(): CharRange = 1..10

fun closedRangeStringFromIntLiteral(): ClosedRange<String> = 1..10

fun intRangeFromLongLiteral(): IntRange = 1L..10L

fun longRangeReturnMismatch(): LongRange {
    return 1..10
}

val longRangeGetterMismatch: LongRange
    get() = 1..10

fun longRangeLocalMismatch() {
    val r: LongRange = 1..10
}
