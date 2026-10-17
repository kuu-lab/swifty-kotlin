@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kuu2589

import kotlinx.io.Buffer
import kotlinx.io.Segment

fun probeBufferHeadAccessors() {
    val empty = Buffer()
    val initial: Segment? = empty.head
    check(initial == null) { "new Buffer.head must be null" }

    val source = Buffer().apply { write(byteArrayOf(11, 22, 33)) }
    val segment: Segment? = source.head
    check(segment != null) { "writing bytes must create a head segment" }

    val target = Buffer()
    target.head = segment
    val updated: Segment? = target.head
    check(updated === segment) { "head setter must preserve the assigned segment" }

    target.head = null
    val cleared: Segment? = target.head
    check(cleared == null) { "head setter must accept null" }

    println("headInitiallyNull=true")
    println("headUpdatePreservesIdentity=true")
    println("headSetterAcceptsNull=true")
}
