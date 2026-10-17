@file:OptIn(kotlinx.io.UnsafeIoApi::class)
package io_gate.segmentreadcontext.consumer

import kotlinx.io.Buffer
import kotlinx.io.Segment
import kotlinx.io.unsafe.SegmentReadContext
import io_gate.segmentreadcontext.producer.readFromSegments

fun readUnchecked(context: SegmentReadContext, segment: Segment, offset: Int): Byte =
    context.getUnchecked(segment, offset)

fun forwardSegments(
    buffer: Buffer,
    action: (context: SegmentReadContext, segment: Segment) -> Unit,
) {
    readFromSegments(buffer, action)
}

fun main() {}
