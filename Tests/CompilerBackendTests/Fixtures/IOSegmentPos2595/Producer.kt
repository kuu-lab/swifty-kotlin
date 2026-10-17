@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kuu2595

import kotlinx.io.*

fun probeSegmentPos() {
    val buffer = Buffer().apply { write(byteArrayOf(13, 26, 39, 52)) }
    val segment = buffer.head ?: error("expected a head segment")

    val initialPos = segment.pos
    val firstByte = buffer.readByte().toInt()
    val afterReadPos = segment.pos
    segment.pos = 2
    val afterSetPos = segment.pos
    val secondByte = buffer.readByte().toInt()
    val afterSecondReadPos = segment.pos

    check(initialPos == 0) { "unexpected initial pos: $initialPos" }
    check(firstByte == 13 && afterReadPos == 1) {
        "reading the first byte should advance pos: byte=$firstByte pos=$afterReadPos"
    }
    check(afterSetPos == 2) { "setting pos should update its getter: $afterSetPos" }
    check(secondByte == 39 && afterSecondReadPos == 3) {
        "reading after setting pos should use the new position: byte=$secondByte pos=$afterSecondReadPos"
    }

    println("initialPos=$initialPos")
    println("read=$firstByte")
    println("afterReadPos=$afterReadPos")
    println("afterSetPos=$afterSetPos")
    println("readAfterSet=$secondByte")
    println("finalPos=$afterSecondReadPos")
}
