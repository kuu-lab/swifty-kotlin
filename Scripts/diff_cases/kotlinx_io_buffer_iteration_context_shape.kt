import kotlinx.io.Buffer
import kotlinx.io.Segment
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.BufferIterationContext
import kotlinx.io.unsafe.SegmentReadContext
import kotlinx.io.unsafe.SegmentWriteContext
import kotlinx.io.unsafe.UnsafeBufferOperations

// IO-GATE KUU-2610: dedicated shape probe for the @UnsafeIoApi interface
// kotlinx.io.unsafe.BufferIterationContext : SegmentReadContext.
//
// Ledger rows: jvm-f4f1bc70601b0f2e / klib-3f0132b282858278. The probe checks
// the interface-inheritance edge that instantiation or callback usage alone
// does not pin: the supertype relation (static upcast and runtime `is`), the
// `next` declaration seen through the interface, the absence of the sibling
// SegmentWriteContext supertype, and that a user-written implementation needs
// exactly `getUnchecked` (inherited) plus `next` (declared).

@OptIn(UnsafeIoApi::class)
private fun readThroughSupertype(context: SegmentReadContext, segment: Segment, offset: Int): Byte =
    context.getUnchecked(segment, offset)

@OptIn(UnsafeIoApi::class)
private fun nextThroughInterface(context: BufferIterationContext, segment: Segment): Segment? =
    context.next(segment)

// A user-written implementation: compiles only when the abstract members are
// exactly SegmentReadContext.getUnchecked and BufferIterationContext.next.
@OptIn(UnsafeIoApi::class)
private class DelegatingIterationContext(private val delegate: BufferIterationContext) : BufferIterationContext {
    var getCalls = 0
    var nextCalls = 0

    override fun getUnchecked(segment: Segment, offset: Int): Byte {
        getCalls++
        return delegate.getUnchecked(segment, offset)
    }

    override fun next(segment: Segment): Segment? {
        nextCalls++
        return delegate.next(segment)
    }
}

@OptIn(UnsafeIoApi::class)
fun main() {
    val buffer = Buffer()
    buffer.write(byteArrayOf(1, 2, 3, 4, 5))

    var runtimeIsRead = false
    var runtimeIsWrite = true
    var throughSupertype = 0
    var throughInterface = 0
    var wrapperSum = 0
    var wrapperGets = 0
    var wrapperNexts = 0

    UnsafeBufferOperations.iterate(buffer) { context, head ->
        // Static upcast along the declared inheritance edge.
        val asRead: SegmentReadContext = context
        runtimeIsRead = (context as Any) is SegmentReadContext
        // The sibling write interface is not a supertype.
        runtimeIsWrite = (context as Any) is SegmentWriteContext

        var segment = head
        while (segment != null) {
            for (i in 0 until segment.size) {
                throughSupertype += readThroughSupertype(asRead, segment, i)
            }
            segment = nextThroughInterface(context, segment)
        }

        val wrapper = DelegatingIterationContext(context)
        // The wrapper is a BufferIterationContext and a SegmentReadContext.
        val wrapperAsRead: SegmentReadContext = wrapper
        var walk = head
        while (walk != null) {
            for (i in 0 until walk.size) {
                wrapperSum += readThroughSupertype(wrapperAsRead, walk, i)
            }
            throughInterface += walk.size
            walk = nextThroughInterface(wrapper, walk)
        }
        wrapperGets = wrapper.getCalls
        wrapperNexts = wrapper.nextCalls
    }

    println("runtime-is-read:$runtimeIsRead")
    println("runtime-is-write:$runtimeIsWrite")
    println("through-supertype-sum:$throughSupertype")
    println("through-interface-size:$throughInterface")
    println("wrapper-sum:$wrapperSum")
    println("wrapper-get-calls:$wrapperGets")
    println("wrapper-next-calls:$wrapperNexts")
}
