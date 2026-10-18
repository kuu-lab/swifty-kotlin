// IO-GATE consumer fixture (ledger and generator retired); edit by hand.
// These references intentionally omit @OptIn and must retain their upstream opt-in diagnostics.
import kotlinx.io.*
import kotlinx.io.files.*
import kotlinx.io.bytestring.*
import kotlinx.io.unsafe.*
import kotlinx.io.bytestring.unsafe.*
import kotlin.io.encoding.*
import kotlin.time.*
import kotlin.text.*

// Ledger klib-07536a2b0690464c: function SegmentReadContext.withData( segment: Segment, readAction: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Unit ) [annotations: JvmSynthetic,OptIn,UnsafeIoApi]
fun f01_opt_in_klib_07536a2b0690464c(target: SegmentReadContext, api_arg_0: Segment, api_arg_1: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Unit) {
    target.withData(api_arg_0, api_arg_1)
}

// Ledger klib-0f0ae6b0e4f74922: object UnsafeBufferOperations [annotations: OptIn,UnsafeIoApi]
fun f01_opt_in_klib_0f0ae6b0e4f74922() {
    kotlinx.io.unsafe.UnsafeBufferOperations
}

// Ledger klib-3f0132b282858278: interface BufferIterationContext [annotations: UnsafeIoApi]
fun f01_opt_in_klib_3f0132b282858278(value: kotlinx.io.unsafe.BufferIterationContext) {
    value.hashCode()
}

// Ledger klib-41e3c3eeaaba19c0: function Sink.writeToInternalBuffer(lambda: (Buffer) -> Unit) [annotations: DelicateIoApi,OptIn]
fun f01_opt_in_klib_41e3c3eeaaba19c0(target: Sink, api_arg_0: (Buffer) -> Unit) {
    target.writeToInternalBuffer(api_arg_0)
}

// Ledger klib-4ee0099543291bca: interface SegmentWriteContext [annotations: UnsafeIoApi]
fun f01_opt_in_klib_4ee0099543291bca(value: kotlinx.io.unsafe.SegmentWriteContext) {
    value.hashCode()
}

// Ledger klib-f6fe9eab2b16817b: interface SegmentReadContext [annotations: UnsafeIoApi]
fun f01_opt_in_klib_f6fe9eab2b16817b(value: kotlinx.io.unsafe.SegmentReadContext) {
    value.hashCode()
}
