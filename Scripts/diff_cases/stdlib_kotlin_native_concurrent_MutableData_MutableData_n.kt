// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

import kotlinx.cinterop.COpaquePointer
import kotlin.native.concurrent.MutableData

fun appendMutableData(target: MutableData, source: MutableData) {
    target.append(source)
}

fun appendPointer(target: MutableData, pointer: COpaquePointer?, count: Int) {
    target.append(pointer, count)
}

fun appendBytes(target: MutableData, bytes: ByteArray) {
    target.append(bytes)
}

fun appendByteRange(target: MutableData, bytes: ByteArray, fromIndex: Int, toIndex: Int) {
    target.append(bytes, fromIndex, toIndex)
}

fun copyBytes(source: MutableData, output: ByteArray, destinationIndex: Int, startIndex: Int, endIndex: Int) {
    source.copyInto(output, destinationIndex, startIndex, endIndex)
}

fun readByte(source: MutableData, index: Int): Byte = source[index]

fun resetData(source: MutableData) {
    source.reset()
}

fun dataSize(source: MutableData): Int = source.size

fun bufferLockedSize(source: MutableData): Int = source.withBufferLocked { _, size -> size }

fun pointerLockedSize(source: MutableData): Int = source.withPointerLocked { _, size -> size }

fun main() {
    println("MutableData API surface")
}
