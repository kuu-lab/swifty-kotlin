package golden.sema

import kotlinx.cinterop.ULongVar
import kotlinx.cinterop.CValues
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toCValues

@ExperimentalForeignApi
fun convertToNative(ulongs: ULongArray): CValues<ULongVar> = ulongs.toCValues()
