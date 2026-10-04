@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package golden.sema

fun makeUByteArrayFromByteArray(storage: ByteArray): UByteArray = UByteArray(storage)

fun makeEmptyUByteArray(): UByteArray = UByteArray(0)
