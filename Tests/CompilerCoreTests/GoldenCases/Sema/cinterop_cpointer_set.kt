import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.set

fun storeAt(ptr: CPointer<ByteVar>, index: Int, value: ByteVar) {
    ptr[index] = value
}
