import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.toLong

fun pointerToAddr(p: CPointer<ByteVar>?): Long = p.toLong()
