package golden.sema

fun uintRangeContainsUByte(range: UIntRange, value: UByte): Boolean =
    range.contains(value)

fun uintRangeContainsULong(range: UIntRange, value: ULong): Boolean =
    range.contains(value)

fun uintRangeContainsUShort(range: UIntRange, value: UShort): Boolean =
    range.contains(value)

fun uintRangeContainsUByteIn(range: UIntRange, value: UByte): Boolean =
    value in range

fun uintRangeContainsULongIn(range: UIntRange, value: ULong): Boolean =
    value in range

fun uintRangeContainsUShortIn(range: UIntRange, value: UShort): Boolean =
    value in range

fun uintRangeContainsUInt(range: UIntRange, value: UInt): Boolean =
    range.contains(value)

fun uintRangeContainsUIntIn(range: UIntRange, value: UInt): Boolean =
    value in range

fun uintRangeContainsUByteNamed(range: UIntRange, value: UByte): Boolean =
    range.contains(value = value)

fun uintRangeContainsUByteWrongLabel(range: UIntRange, value: UByte): Boolean =
    range.contains(other = value)

fun uintRangeContainsNullableUByte(range: UIntRange, value: UByte?): Boolean =
    range.contains(value)
