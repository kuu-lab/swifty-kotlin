@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlinx.io.Buffer
import kotlinx.io.Segment

private fun newSegment(value: Byte): Segment {
    val buffer = Buffer()
    buffer.writeByte(value)
    return checkNotNull(buffer.head)
}

fun main() {
    val predecessor = newSegment(0x11.toByte())
    val segment = newSegment(0x22.toByte())
    val replacement = newSegment(0x33.toByte())

    val initialPrevious: Segment? = segment.prev
    check(initialPrevious == null) { "a detached segment must have a null predecessor" }

    segment.prev = predecessor
    val linkedPrevious: Segment? = segment.prev
    check(linkedPrevious === predecessor) { "prev getter must return the assigned predecessor" }
    check(predecessor.prev == null) { "a segment at the head must have a null predecessor" }

    segment.prev = replacement
    check(segment.prev === replacement) { "prev setter must replace the predecessor" }

    segment.prev = null
    check(segment.prev == null) { "prev setter must clear the predecessor" }

    println("prev-link=pass")
    println("prev-null=pass")
}
