package golden.sema

fun makeUByteArray(): UByteArray =
    UByteArray(3) { (it + 1).toUByte() }
