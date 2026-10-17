import kotlinx.io.Segment
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.SegmentWriteContext

@OptIn(UnsafeIoApi::class)
fun useAllOverloads(ctx: SegmentWriteContext, segment: Segment) {
    ctx.setUnchecked(segment, 0, 1.toByte())
    ctx.setUnchecked(segment, 1, 1.toByte(), 2.toByte())
    ctx.setUnchecked(segment, 3, 1.toByte(), 2.toByte(), 3.toByte())
    ctx.setUnchecked(segment, 6, 1.toByte(), 2.toByte(), 3.toByte(), 4.toByte())
}
