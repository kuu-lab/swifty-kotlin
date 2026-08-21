@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class, kotlin.ExperimentalUnsignedTypes::class)

package golden.sema

import kotlin.uuid.Uuid

fun uuidInstanceApiSurface(a: Uuid, b: Uuid, other: Any?): String {
    val eq = a.equals(other)
    val same = a == b
    val hash = a.hashCode()
    val cmp = a.compareTo(b)
    val text = a.toString()
    val hex = a.toHexString()
    val hexDash = a.toHexDashString()
    val bytes = a.toByteArray()
    val ubytes = a.toUByteArray()
    val longSum = a.toLongs { msb, lsb -> msb + lsb }
    val ulongSum = a.toULongs { msb, lsb -> msb + lsb }
    return "$eq $same $hash $cmp $text $hex $hexDash ${bytes.size} ${ubytes.size} $longSum $ulongSum"
}
