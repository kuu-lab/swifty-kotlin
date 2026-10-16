// DIFF_CANDIDATE_ONLY_FROM_SOURCE
// EXPECT-STDOUT: SegmentWriteContext declares four direct setUnchecked overloads

import kotlinx.io.Segment
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.SegmentWriteContext

@OptIn(UnsafeIoApi::class)
private fun writeEveryOverload(context: SegmentWriteContext, segment: Segment) {
    context.setUnchecked(segment, 0, 1.toByte())
    context.setUnchecked(segment, 1, 2.toByte(), 3.toByte())
    context.setUnchecked(segment, 3, 4.toByte(), 5.toByte(), 6.toByte())
    context.setUnchecked(segment, 6, 7.toByte(), 8.toByte(), 9.toByte(), 10.toByte())
}

@OptIn(UnsafeIoApi::class)
fun main() {
    println("SegmentWriteContext declares four direct setUnchecked overloads")
}
