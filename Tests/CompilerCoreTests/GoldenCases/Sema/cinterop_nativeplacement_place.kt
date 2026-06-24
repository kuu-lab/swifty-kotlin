package golden.sema

import kotlinx.cinterop.CPointer
import kotlinx.cinterop.CValues
import kotlinx.cinterop.CVariable
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.NativePlacement
import kotlinx.cinterop.place

@ExperimentalForeignApi
fun <T : CVariable> copyValue(placement: NativePlacement, value: CValues<T>): CPointer<T> {
    return placement.place(value)
}
