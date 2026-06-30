package golden.sema

import kotlinx.cinterop.CValue
import kotlinx.cinterop.CVariable
import kotlinx.cinterop.ExperimentalForeignApi

@ExperimentalForeignApi
fun <T : CVariable> applyValue(value: CValue<T>, location: T) {
    value.write(location)
}
