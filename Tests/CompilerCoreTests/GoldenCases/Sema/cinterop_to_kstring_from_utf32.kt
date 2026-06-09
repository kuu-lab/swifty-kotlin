package golden.sema

import kotlinx.cinterop.CPointer
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.IntVar
import kotlinx.cinterop.toKStringFromUtf32

@ExperimentalForeignApi
fun decodeUtf32(ptr: CPointer<IntVar>): String = ptr.toKStringFromUtf32()
