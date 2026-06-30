package golden.sema

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.NativePtr
import kotlinx.cinterop.writeBits

@ExperimentalForeignApi
fun testWriteBits(ptr: NativePtr) {
    writeBits(ptr, 0L, 8, 42L)
}
