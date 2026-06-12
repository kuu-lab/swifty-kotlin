import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.toCValues

fun usePtrs(ptrs: Array<CPointer<ByteVar>?>) {
    ptrs.toCValues()
}
