package golden.sema

fun makeULongRange(start: ULong, endInclusive: ULong): ULongRange =
    ULongRange(start, endInclusive)

fun acceptULongRangeProgression(range: ULongProgression): Boolean = true

fun acceptULongRangeClosedRange(range: ClosedRange<ULong>): Boolean = true

fun acceptULongRangeCompanion(companion: Any): Boolean = true

fun useULongRangeCompanion(): Any = ULongRange.Companion
