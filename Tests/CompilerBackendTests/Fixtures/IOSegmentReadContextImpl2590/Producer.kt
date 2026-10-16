@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@file:OptIn(kotlinx.io.UnsafeIoApi::class)

package kuu2590

import kotlinx.io.Buffer
import kotlinx.io.unsafe.SegmentReadContext
import kotlinx.io.unsafe.SegmentReadContextImpl

fun probeSegmentReadContextImpl() {
    val buffer = Buffer().apply { write(byteArrayOf(17, 34, 51)) }
    val segment = buffer.head ?: error("expected a head segment")
    val offset = segment.pos

    val first: SegmentReadContext = SegmentReadContextImpl
    val second: SegmentReadContext = SegmentReadContextImpl
    check(first === second) { "SegmentReadContextImpl must return its singleton" }

    val observed = (0..2).map { index -> first.getUnchecked(segment, offset + index).toInt() }
    check(observed == listOf(17, 34, 51)) { "unexpected getUnchecked values: $observed" }

    println("identity=true")
    println("getUnchecked=${observed.joinToString(",")}")
}
