/* Derived from kotlinx-io 0.9.1 under the Apache-2.0 license. */
package kotlinx.io.bytestring.unsafe

import kotlinx.io.bytestring.ByteString

@UnsafeByteStringApi
public object UnsafeByteStringOperations {
    public fun wrapUnsafe(array: ByteArray): ByteString = ByteString.wrap(array)

    public inline fun withByteArrayUnsafe(byteString: ByteString, block: (ByteArray) -> Unit) {
        block(byteString.getBackingArrayReference())
    }
}
