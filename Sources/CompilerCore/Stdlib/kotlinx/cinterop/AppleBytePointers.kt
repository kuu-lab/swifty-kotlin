@file:OptIn(ExperimentalForeignApi::class)
package kotlinx.cinterop
public fun Pinned<ByteArray>.addressOf(index: Int): CPointer<ByteVar> =
    platform.Foundation.__foundation_pinned_bytes_address(this, index)
private class ByteArrayNativeReference(val array: ByteArray, val index: Int) : CValuesRef<ByteVarOf<Byte>>()
public fun ByteArray.refTo(index: Int): CValuesRef<ByteVar> {
    require(index >= 0 && index < size) { "ByteArray.refTo index out of bounds: $index" }
    return ByteArrayNativeReference(this, index)
}
internal fun __byteArrayRefPointer(reference: CValuesRef<ByteVar>): CPointer<ByteVar> {
    require(reference is ByteArrayNativeReference) { "Expected a ByteArray reference" }
    return reference.array.usePinned { it.addressOf(reference.index) }
}
public fun CPointer<ByteVar>.readBytes(count: Int): ByteArray {
    val result = ByteArray(count)
    result.usePinned { platform.posix.memcpy(it.addressOf(0), this, count.toULong()) }
    return result
}
public operator fun CPointer<UByteVar>.plus(index: Int): CPointer<UByteVar> =
    platform.Foundation.__foundation_byte_pointer_add(this, index).reinterpret()
public operator fun CPointer<ByteVar>.plus(index: Int): CPointer<ByteVar> =
    platform.Foundation.__foundation_byte_pointer_add(this, index)
public operator fun CPointer<ByteVar>.get(index: Int): Byte = (this + index).pointed.value
