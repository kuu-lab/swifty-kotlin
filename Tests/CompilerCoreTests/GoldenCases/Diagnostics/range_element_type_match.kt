package golden.diagnostics

fun intRangeFromIntLiteral(): IntRange = 1..10

fun longRangeFromLongLiteral(): LongRange = 1L..10L

fun uintRangeFromUIntLiteral(): UIntRange = 1u..10u

fun charRangeFromCharLiteral(): CharRange = 'a'..'z'

fun intProgressionFromStep(): IntProgression = 1..10 step 2

fun intProgressionFromDownTo(): IntProgression = 10 downTo 1

fun intRangeFromUntil(): IntRange = 1 until 10

fun closedRangeIntFromIntLiteral(): ClosedRange<Int> = 1..10

fun closedFloatingPointRangeFromDoubleLiteral(): ClosedFloatingPointRange<Double> = 1.0..10.0

fun closedRangeDoubleFromDoubleLiteral(): ClosedRange<Double> = 1.0..10.0
