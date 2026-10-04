package golden.sema

fun makeUIntRange(start: UInt, endInclusive: UInt): UIntRange =
    UIntRange(start, endInclusive)

fun acceptUIntRangeProgression(range: UIntProgression): Boolean = true

fun acceptUIntRangeClosedRange(range: ClosedRange<UInt>): Boolean = true

fun acceptUIntRangeCompanion(companion: Any): Boolean = true

fun useUIntRangeCompanion(): Any = UIntRange.Companion
