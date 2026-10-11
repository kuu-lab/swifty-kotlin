@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
package kotlinx.io
import kotlin.test.*
fun segmentSizes(buffer: Buffer): List<Int> {
    var segment: Segment? = buffer.head ?: return emptyList()

    val sizes = mutableListOf(segment!!.limit - segment.pos)
    segment = segment.next
    while (segment != null) {
        sizes.add(segment.limit - segment.pos)
        segment = segment.next
    }
    return sizes
}

fun assertNoEmptySegments(buffer: Buffer) {
    assertTrue(segmentSizes(buffer).all { it != 0 }, "Expected all segments to be non-empty")
}
