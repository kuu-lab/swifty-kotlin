package golden.sema

fun useCharProgressionCompanion(): Any = CharProgression.Companion

fun useUIntRangeCompanion(): Any = UIntRange.Companion

fun makeUIntRange(start: UInt, endInclusive: UInt): UIntRange =
    UIntRange(start, endInclusive)

fun acceptCharProgression(progression: CharProgression): Boolean = true

fun genericRangeTo(start: String, endInclusive: String): ClosedRange<String> =
    start.rangeTo(endInclusive)

fun genericRangeUntil(start: String, endExclusive: String): OpenEndRange<String> =
    start.rangeUntil(endExclusive)

fun genericCoerceAtLeast(value: String, minimum: String): String =
    value.coerceAtLeast(minimum)

fun genericCoerceAtMost(value: String, maximum: String): String =
    value.coerceAtMost(maximum)

fun genericCoerceInClosedRange(value: String, range: ClosedRange<String>): String =
    value.coerceIn(range)

fun genericCoerceInBounds(value: String, minimum: String?, maximum: String?): String =
    value.coerceIn(minimum, maximum)
