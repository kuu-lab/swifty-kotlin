/* Derived from kotlinx-io 0.9.1 under the Apache-2.0 license. */
package kotlinx.io.bytestring.unsafe

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind.EXACTLY_ONCE
import kotlin.contracts.contract
import kotlinx.io.bytestring.ByteString

@UnsafeByteStringApi
@OptIn(ExperimentalContracts::class)
public object UnsafeByteStringOperations {
    public fun wrapUnsafe(array: ByteArray): ByteString = ByteString.wrap(array)

    public inline fun withByteArrayUnsafe(byteString: ByteString, block: (ByteArray) -> Unit) {
        contract {
            callsInPlace(block, EXACTLY_ONCE)
        }
        block(byteString.getBackingArrayReference())
    }
}
