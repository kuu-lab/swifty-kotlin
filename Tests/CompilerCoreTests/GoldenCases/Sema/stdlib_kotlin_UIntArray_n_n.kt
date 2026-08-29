package golden.sema

fun makeUIntArraySizeOnly(): UIntArray = UIntArray(3)

fun makeUIntArrayFromIntView(source: IntArray): UIntArray = source.asUIntArray()
