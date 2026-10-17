@file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)
@file:Suppress("INVISIBLE_MEMBER")

package kotlinx.io.bytestring.probe

import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

public inline fun publishedBackingArrayForProbe(bytes: ByteString): ByteArray =
    bytes.getBackingArrayReference()

public fun backingArrayIdentityProbe(): String {
    val backing = byteArrayOf(0x12, 0x80.toByte(), 0xff.toByte())
    val bytes = UnsafeByteStringOperations.wrapUnsafe(backing)
    val directIdentity = directBackingArrayIdentity(bytes, backing)
    val firstPublishedResult = publishedBackingArrayForProbe(bytes)
    val secondPublishedResult = publishedBackingArrayForProbe(bytes)
    val publishedIdentity = firstPublishedResult === backing && secondPublishedResult === backing
    return "PASS:direct=$directIdentity:inline=$publishedIdentity:repeat=${firstPublishedResult === secondPublishedResult}"
}
