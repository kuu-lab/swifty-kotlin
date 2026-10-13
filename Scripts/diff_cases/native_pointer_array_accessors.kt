// DIFF_CANDIDATE_ONLY: Kotlin/Native pointer array accessors have no JVM kotlinc oracle.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: native_pointer_array_accessors.expected.stdout
@file:OptIn(kotlin.native.ExperimentalNativeApi::class, kotlin.ExperimentalUnsignedTypes::class)

import kotlin.native.getByteAt
import kotlin.native.setByteAt
import kotlin.native.getShortAt
import kotlin.native.setShortAt
import kotlin.native.getIntAt
import kotlin.native.setIntAt
import kotlin.native.getLongAt
import kotlin.native.setLongAt
import kotlin.native.getCharAt
import kotlin.native.setCharAt
import kotlin.native.getFloatAt
import kotlin.native.setFloatAt
import kotlin.native.getDoubleAt
import kotlin.native.setDoubleAt
import kotlin.native.getUByteAt
import kotlin.native.setUByteAt
import kotlin.native.getUShortAt
import kotlin.native.setUShortAt
import kotlin.native.getUIntAt
import kotlin.native.setUIntAt
import kotlin.native.getULongAt
import kotlin.native.setULongAt

fun probe(bytes: ByteArray): String {
    bytes.setByteAt(0, 1)
    bytes.setShortAt(0, 2)
    bytes.setIntAt(0, 3)
    bytes.setLongAt(0, 4L)
    bytes.setCharAt(0, 'a')
    bytes.setFloatAt(0, 1.5f)
    bytes.setDoubleAt(0, 2.5)
    bytes.setUByteAt(0, 1u)
    bytes.setUShortAt(0, 2u)
    bytes.setUIntAt(0, 3u)
    bytes.setULongAt(0, 4uL)
    return "${bytes.getByteAt(0)}${bytes.getShortAt(0)}${bytes.getIntAt(0)}" +
        "${bytes.getLongAt(0)}${bytes.getCharAt(0).code}${bytes.getFloatAt(0)}" +
        "${bytes.getDoubleAt(0)}${bytes.getUByteAt(0)}${bytes.getUShortAt(0)}" +
        "${bytes.getUIntAt(0)}${bytes.getULongAt(0)}"
}

fun main() {
    println(probe(ByteArray(64)))
}
