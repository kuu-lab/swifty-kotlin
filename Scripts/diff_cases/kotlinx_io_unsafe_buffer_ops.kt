import kotlinx.io.Buffer
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.UnsafeBufferOperations
import kotlinx.io.unsafe.SegmentReadContext
import kotlinx.io.unsafe.SegmentWriteContext
import kotlinx.io.unsafe.withData

// Exercises kotlinx.io.unsafe.UnsafeBufferOperations: moveToTail, readFromHead,
// writeToTail, iterate, forEachSegment and the unchecked context accessors.

@OptIn(UnsafeIoApi::class)
fun main() {
    println(UnsafeBufferOperations.maxSafeWriteCapacity)

    val buf = Buffer()
    UnsafeBufferOperations.moveToTail(buf, byteArrayOf(10, 20, 30, 40, 50))
    println(buf.size)

    val consumed = UnsafeBufferOperations.readFromHead(buf) { data, pos, limit ->
        var sum = 0
        var i = pos
        while (i < pos + 3) {
            sum += data[i]
            i++
        }
        println(sum)
        3
    }
    println(consumed)
    println(buf.size)

    val written = UnsafeBufferOperations.writeToTail(buf, 4) { data, pos, limit ->
        data[pos] = 7
        data[pos + 1] = 8
        2
    }
    println(written)
    println(buf.size)

    var sum = 0
    UnsafeBufferOperations.iterate(buf) { ctx, head ->
        var seg = head
        while (seg != null) {
            var i = 0
            while (i < seg.size) {
                sum += ctx.getUnchecked(seg, i)
                i++
            }
            seg = ctx.next(seg)
        }
    }
    println(sum)

    var segCount = 0
    UnsafeBufferOperations.forEachSegment(buf) { ctx, segment ->
        segCount++
        println(ctx.withData(segment) { data, start, end -> end - start })
    }
    println(segCount)

    UnsafeBufferOperations.iterate(buf, 2L) { ctx, segment, startOffset ->
        println(startOffset)
        println(ctx.getUnchecked(segment!!, 0))
    }

    val w2 = UnsafeBufferOperations.writeToTail(buf, 4) { ctx, segment ->
        ctx.setUnchecked(segment, 0, 1.toByte())
        ctx.setUnchecked(segment, 1, 2.toByte(), 3.toByte())
        ctx.setUnchecked(segment, 3, 4.toByte(), 5.toByte(), 6.toByte(), 7.toByte())
        6
    }
    println(w2)

    val last = UnsafeBufferOperations.readFromHead(buf) { ctx, segment ->
        println(ctx.getUnchecked(segment, 0))
        buf.size.toInt()
    }
    println(last)
    println(buf.size)
    println(buf.exhausted())
}
