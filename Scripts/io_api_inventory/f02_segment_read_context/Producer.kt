@file:OptIn(kotlinx.io.UnsafeIoApi::class)
package io_gate.segmentreadcontext.producer

import kotlinx.io.Buffer
import kotlinx.io.Segment
import kotlinx.io.unsafe.SegmentReadContext
import kotlinx.io.unsafe.UnsafeBufferOperations

interface SegmentReadContextSubinterface : SegmentReadContext

fun readFromSegments(
    buffer: Buffer,
    action: (context: SegmentReadContext, segment: Segment) -> Unit,
) {
    UnsafeBufferOperations.forEachSegment(buffer, action)
}
