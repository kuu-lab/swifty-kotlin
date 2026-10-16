@file:Suppress("INVISIBLE_MEMBER")

package kotlinx.io.bytestring.probe

import kotlinx.io.bytestring.ByteString

public inline fun directBackingArrayIdentity(bytes: ByteString, expected: ByteArray): Boolean =
    bytes.getBackingArrayReference() === expected
