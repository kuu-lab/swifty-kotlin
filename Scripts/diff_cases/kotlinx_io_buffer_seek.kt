@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlinx.io.Buffer
import kotlinx.io.Segment
import kotlinx.io.seek

private const val SEGMENT_SIZE = 8192

fun main() {
    val empty = Buffer()
    var emptyCalls = 0
    val emptyResult = empty.seek(0L) { segment, offset ->
        emptyCalls += 1
        check(segment == null)
        check(offset == -1L)
        "empty:$offset"
    }
    check(emptyCalls == 1)
    check(emptyResult == "empty:-1")

    val bytes = ByteArray(SEGMENT_SIZE * 3) { index ->
        when (index / SEGMENT_SIZE) {
            0 -> 'a'.code.toByte()
            1 -> 'b'.code.toByte()
            else -> 'c'.code.toByte()
        }
    }
    val buffer = Buffer()
    buffer.write(bytes, 0, bytes.size)
    check(buffer.size == bytes.size.toLong())

    val forwardIndex = SEGMENT_SIZE.toLong() + 7L
    val expectedForwardOffset = SEGMENT_SIZE.toLong()
    val forwardSegment: Segment?
    val forwardOffset: Long
    var forwardCalls = 0
    val forwardResult = buffer.seek(forwardIndex) { segment, offset ->
        forwardCalls += 1
        forwardSegment = segment
        forwardOffset = offset
        check(segment != null)
        check(offset == expectedForwardOffset)
        "forward:${segment != null}:$offset"
    }
    check(forwardCalls == 1)
    check(forwardSegment != null)
    check(forwardOffset == expectedForwardOffset)
    check(forwardResult == "forward:true:$expectedForwardOffset")

    val boundaryIndex = SEGMENT_SIZE.toLong()
    var boundaryCalls = 0
    val boundaryResult = buffer.seek(boundaryIndex) { segment, offset ->
        boundaryCalls += 1
        check(segment != null)
        check(offset == boundaryIndex)
        "boundary:${segment != null}:$offset"
    }
    check(boundaryCalls == 1)
    check(boundaryResult == "boundary:true:$boundaryIndex")

    val backwardIndex = SEGMENT_SIZE.toLong() * 2L + 7L
    val expectedBackwardOffset = SEGMENT_SIZE.toLong() * 2L
    val backwardSegment: Segment?
    val backwardOffset: Long
    var backwardCalls = 0
    val backwardResult = buffer.seek(backwardIndex) { segment, offset ->
        backwardCalls += 1
        backwardSegment = segment
        backwardOffset = offset
        check(segment != null)
        check(offset == expectedBackwardOffset)
        "backward:${segment != null}:$offset"
    }
    check(backwardCalls == 1)
    check(backwardSegment != null)
    check(backwardOffset == expectedBackwardOffset)
    check(backwardResult == "backward:true:$expectedBackwardOffset")

    println("empty=$emptyResult:$emptyCalls")
    println("forward=$forwardResult:$forwardCalls")
    println("boundary=$boundaryResult:$boundaryCalls")
    println("backward=$backwardResult:$backwardCalls")
}
