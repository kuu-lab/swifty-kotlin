package golden.sema

import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.CValues
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toCValues

@ExperimentalForeignApi
fun convertToNative(ubytes: UByteArray): CValues<UByteVar> = ubytes.toCValues()
