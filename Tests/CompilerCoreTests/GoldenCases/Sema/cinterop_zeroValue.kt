package golden.sema

import kotlinx.cinterop.CValue
import kotlinx.cinterop.CVariable
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.zeroValue

@ExperimentalForeignApi
fun <T : CVariable> makeZero(): CValue<T> = zeroValue()
