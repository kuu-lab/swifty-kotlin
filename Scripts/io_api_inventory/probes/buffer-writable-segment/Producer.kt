@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")

package bufferwritablesegmentprobe

import kotlinx.io.Buffer
import kotlinx.io.Segment
import kotlinx.io.SegmentPool

fun runInvalidCapacityProbe() {
    for (minimumCapacity in listOf(-1, 0, Segment.SIZE + 1)) {
        val buffer = Buffer()
        var failure: IllegalArgumentException? = null
        try {
            buffer.writableSegment(minimumCapacity)
        } catch (caught: IllegalArgumentException) {
            failure = caught
        }
        check(failure != null) { "minimumCapacity $minimumCapacity was accepted" }
        check(failure.message == "unexpected capacity ($minimumCapacity), should be in range [1, ${Segment.SIZE}]")
        println("invalid-capacity:$minimumCapacity:${failure.message}")
    }
}

fun runEmptyTailProbe() {
    val buffer = Buffer()
    val segment = buffer.writableSegment(1)
    check(buffer.head === segment)
    check(buffer.tail === segment)
    check(segment.limit == 0)
    check(buffer.size == 0L)
    println("empty-tail:head-and-tail-identify-returned-segment")
}

private fun seedBufferTail(buffer: Buffer, segment: Segment) {
    buffer.head = segment
    buffer.tail = segment
    segment.prev = segment
    segment.next = segment
}

fun runTailReuseAndAppendProbe() {
    val exactFitBuffer = Buffer()
    val exactFitTail = SegmentPool.take()
    seedBufferTail(exactFitBuffer, exactFitTail)
    val maximumCapacityTail = exactFitBuffer.writableSegment(Segment.SIZE)
    check(maximumCapacityTail === exactFitTail)
    println("maximum-capacity:existing-empty-tail-reused")

    exactFitTail.limit = Segment.SIZE - 1
    val exactFit = exactFitBuffer.writableSegment(1)
    check(exactFit === exactFitTail)
    check(exactFitBuffer.tail === exactFitTail)
    println("exact-fit:existing-tail-reused")

    exactFitTail.limit = Segment.SIZE
    val appended = exactFitBuffer.writableSegment(1)
    check(appended !== exactFitTail)
    check(exactFitBuffer.head === exactFitTail)
    check(exactFitBuffer.tail === appended)
    check(exactFitTail.next === appended)
    check(appended.prev === exactFitTail)
    check(appended.next === exactFitTail)
    check(exactFitTail.prev === appended)
    check(appended.limit == 0)
    println("insufficient-capacity:new-tail-linked")

    val nonOwnerBuffer = Buffer()
    val nonOwnerTail = SegmentPool.take()
    seedBufferTail(nonOwnerBuffer, nonOwnerTail)
    nonOwnerTail.owner = false
    val nonOwnerAppend = nonOwnerBuffer.writableSegment(1)
    check(nonOwnerAppend !== nonOwnerTail)
    check(nonOwnerBuffer.tail === nonOwnerAppend)
    check(nonOwnerTail.next === nonOwnerAppend)
    check(nonOwnerAppend.prev === nonOwnerTail)
    println("non-owner:new-tail-linked")
}
