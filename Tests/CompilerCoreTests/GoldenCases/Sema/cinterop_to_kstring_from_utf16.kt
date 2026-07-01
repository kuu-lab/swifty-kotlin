package golden.sema

import kotlinx.cinterop.CPointer
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.UShortVar
import kotlinx.cinterop.toKStringFromUtf16

@ExperimentalForeignApi
fun decodeUtf16(ptr: CPointer<UShortVar>): String = ptr.toKStringFromUtf16()
