@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlinx.io.Buffer
import kotlinx.io.Segment

private fun newSegment(seed: Byte): Segment {
    val buffer = Buffer()
    buffer.writeByte(seed)
    return checkNotNull(buffer.head)
}

fun main() {
    val first = newSegment(0x11.toByte())
    val second = newSegment(0x22.toByte())

    first.next = second
    check(first.next === second)
    check(second.next == null)

    first.next = null
    check(first.next == null)

    println("next-link=pass")
    println("next-null=pass")
}
