package golden.sema

fun makeUIntArray(size: Int): UIntArray = UIntArray(size) { index ->
    (index + 1).toUInt()
}
