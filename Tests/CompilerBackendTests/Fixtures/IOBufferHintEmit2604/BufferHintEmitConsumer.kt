@file:OptIn(kotlinx.io.InternalIoApi::class)

package kuu2604

import kotlinx.io.Buffer

fun verifyBufferHintEmitNonDestructive() {
    check(producerBoundaryMarker() == 2604)

    val empty = Buffer()
    check(empty.size == 0L)
    empty.hintEmit()
    check(empty.size == 0L)
    empty.hintEmit()
    check(empty.size == 0L)
    println("empty:size=0;bytes=0")

    val nonEmpty = Buffer()
    nonEmpty.writeByte(18.toByte())
    nonEmpty.writeByte(52.toByte())
    nonEmpty.writeByte((-1).toByte())
    nonEmpty.writeByte(0.toByte())
    check(nonEmpty.size == 4L)
    nonEmpty.hintEmit()
    check(nonEmpty.size == 4L)
    nonEmpty.hintEmit()
    val preservedSize = nonEmpty.size
    check(preservedSize == 4L)
    val first = nonEmpty.readByte().toInt()
    val second = nonEmpty.readByte().toInt()
    val third = nonEmpty.readByte().toInt()
    val fourth = nonEmpty.readByte().toInt()
    check(first == 18 && second == 52 && third == -1 && fourth == 0)
    check(nonEmpty.size == 0L)
    println("non-empty:size=4;bytes=18,52,-1,0")
}

fun main() {
    verifyBufferHintEmitNonDestructive()
}
