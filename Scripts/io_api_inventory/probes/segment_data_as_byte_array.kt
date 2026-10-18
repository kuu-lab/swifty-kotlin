@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")

import kotlinx.io.Segment

fun main() {
    val segment = Segment.new()
    segment.writeByte(0x2a.toByte())

    val readOnlyView: ByteArray = segment.dataAsByteArray(readOnly = true)
    val writableView: ByteArray = segment.dataAsByteArray(readOnly = false)

    check(readOnlyView === writableView) {
        "readOnly=true and readOnly=false must return the same backing array"
    }
    check(readOnlyView[0] == 0x2a.toByte()) {
        "the returned view must expose the segment's readable byte"
    }

    writableView[0] = 0x2b.toByte()
    check(segment.readByte() == 0x2b.toByte()) {
        "writes through the returned view must update the segment's data"
    }

    println("PASS: Segment.dataAsByteArray returns the backing ByteArray view")
}
