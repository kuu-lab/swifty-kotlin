package kotlinx.cinterop

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_byteArray_toKString")
internal external fun ByteArray.__kk_byteArray_toKString(startIndex: Int, endIndex: Int, throwOnInvalidSequence: Boolean): String

public fun ByteArray.toKString(
    startIndex: Int = 0,
    endIndex: Int = this.size,
    throwOnInvalidSequence: Boolean = false
): String {
    if (startIndex < 0 || endIndex > this.size || startIndex > endIndex) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: ${this.size}")
    }
    return this.__kk_byteArray_toKString(startIndex, endIndex, throwOnInvalidSequence)
}
