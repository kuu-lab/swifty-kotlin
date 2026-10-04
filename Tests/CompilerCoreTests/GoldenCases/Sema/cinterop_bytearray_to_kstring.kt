package golden.sema

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toKString

@ExperimentalForeignApi
fun decodeBytes(bytes: ByteArray): String = bytes.toKString()
