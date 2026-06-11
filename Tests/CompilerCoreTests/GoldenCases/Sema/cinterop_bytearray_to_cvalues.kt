package golden.sema

import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CValues
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toCValues

@ExperimentalForeignApi
fun convertToNative(bytes: ByteArray): CValues<ByteVar> = bytes.toCValues()
