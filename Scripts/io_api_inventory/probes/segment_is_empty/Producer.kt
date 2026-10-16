@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kuu2593.segmentisempty

import kotlinx.io.SegmentPool
import kotlinx.io.isEmpty

fun segmentIsEmptyProbe() {
    val segment = SegmentPool.take()
    try {
        check(segment.isEmpty())
        println("empty=true")

        segment.writeByte(65.toByte())
        check(!segment.isEmpty())
        println("nonempty=false")

        check(segment.readByte() == 65.toByte())
        check(segment.isEmpty())
        println("consumed=true")
    } finally {
        SegmentPool.recycle(segment)
    }
}
