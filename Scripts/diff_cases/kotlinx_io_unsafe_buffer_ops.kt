import kotlinx.io.Buffer
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.UnsafeBufferOperations
import kotlinx.io.unsafe.withData

// Exercises kotlinx.io.unsafe.UnsafeBufferOperations: moveToTail, readFromHead,
// writeToTail, iterate, forEachSegment and the unchecked context accessors.

private inline fun <T> withNestedOffset(action: (Int) -> T): T = action(0)

private fun Buffer.readByteArray(): ByteArray = ByteArray(size.toInt()) { readByte() }

@OptIn(UnsafeIoApi::class)
private fun firstMatchingByteWithNestedInlineCallbacks(buffer: Buffer, target: Byte): Int {
    var inspected = 0
    UnsafeBufferOperations.forEachSegment(buffer) { ctx, segment ->
        ctx.withData(segment) { data, startIndex, endIndex ->
            var index = startIndex
            while (index < endIndex) {
                inspected++
                withNestedOffset { nestedOffset ->
                    if (data[index + nestedOffset] == target) return inspected
                }
                index++
            }
        }
    }
    return 0
}

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

    val sizeBeforeLookup = buf.size
    println(firstMatchingByteWithNestedInlineCallbacks(buf, 40))
    println(buf.size == sizeBeforeLookup)

    val last = UnsafeBufferOperations.readFromHead(buf) { ctx, segment ->
        println(ctx.getUnchecked(segment, 0))
        segment.size
    }
    println(last)
    println(buf.size)
    val remaining = buf.readByteArray()
    println(remaining.joinToString(",") { it.toInt().toString() })
    println(buf.size)
    println(buf.exhausted())
}
