@file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)

package kotlinx.io.bytestring.wrapunsafe

import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

public fun wrapUnsafeByteArrayAlias(): String {
    val input = byteArrayOf(0x12, 0x34)
    val wrapped = UnsafeByteStringOperations.wrapUnsafe(input)
    val copied = ByteString(input)
    val initialValuesMatch = wrapped.size == input.size && wrapped[0] == input[0] && wrapped[1] == input[1]

    input[0] = 0x7f
    val mutationIsVisible = wrapped[0] == 0x7f.toByte() && wrapped[1] == 0x34.toByte()
    val copyIsIndependent = copied[0] == 0x12.toByte() && copied[1] == 0x34.toByte()

    return "PASS:size=${wrapped.size == input.size}:initial=$initialValuesMatch:alias=$mutationIsVisible:copy-control=$copyIsIndependent"
}
