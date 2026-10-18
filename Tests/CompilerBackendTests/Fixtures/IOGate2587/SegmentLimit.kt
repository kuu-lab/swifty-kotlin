@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlinx.io.Buffer
import kotlinx.io.Segment

private fun segmentWithBytes(): Pair<Buffer, Segment> {
    val buffer = Buffer()
    buffer.write(byteArrayOf(17, 34, 51, 68))
    return buffer to checkNotNull(buffer.head)
}

fun main() {
    val (shrinkingBuffer, shrinkingSegment) = segmentWithBytes()
    check(shrinkingSegment.limit == 4)
    check(shrinkingSegment.size == 4)
    shrinkingSegment.limit = 2
    check(shrinkingSegment.limit == 2)
    check(shrinkingSegment.size == 2)
    println("limit-shrink=${shrinkingSegment.limit}:${shrinkingSegment.size}")

    val (restoringBuffer, restoringSegment) = segmentWithBytes()
    restoringSegment.limit = 2
    check(restoringSegment.limit == 2)
    check(restoringSegment.size == 2)
    restoringSegment.limit = 4
    check(restoringSegment.limit == 4)
    check(restoringSegment.size == 4)
    check(restoringBuffer.size == 4L)
    println("limit-restore=${restoringSegment.limit}:${restoringSegment.size}:${restoringBuffer.size}")
    val bytes = ByteArray(4)
    check(restoringBuffer.readAtMostTo(bytes, 0, bytes.size) == bytes.size)
    check(bytes.joinToString(",") == "17,34,51,68")
    println("limit-bytes=${bytes.joinToString(",")}")
}
