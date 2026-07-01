package golden.sema

import kotlinx.cinterop.UIntVar
import kotlinx.cinterop.CValues
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toCValues

@ExperimentalForeignApi
fun convertToNative(uints: UIntArray): CValues<UIntVar> = uints.toCValues()
