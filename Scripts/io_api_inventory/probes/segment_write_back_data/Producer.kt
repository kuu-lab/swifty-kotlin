@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kuu2588.segmentwritebackdata

import kotlinx.io.SegmentPool

fun segmentWriteBackDataProbe() {
    val segment = SegmentPool.take()
    try {
        val data = segment.dataAsByteArray(false)
        val start = segment.limit
        data[start] = 65.toByte()
        data[start + 1] = 66.toByte()

        val bytesToCommit = 2
        val result: Unit = segment.writeBackData(data, bytesToCommit)
        check(result == Unit)
        check(segment.size == 0)
        check(segment.limit == start)
        println("write-back-return=Unit")
        println("before-commit=0")

        segment.limit += bytesToCommit
        check(segment.size == 2)
        check(segment.readByte() == 65.toByte())
        check(segment.readByte() == 66.toByte())
        println("committed=65,66")

        val emptySegment = SegmentPool.take()
        try {
            val emptyData = emptySegment.dataAsByteArray(false)
            val emptyLimit = emptySegment.limit
            val emptyResult: Unit = emptySegment.writeBackData(emptyData, 0)
            check(emptyResult == Unit)
            check(emptySegment.size == 0)
            check(emptySegment.limit == emptyLimit)
            println("zero-commit=unchanged")
        } finally {
            SegmentPool.recycle(emptySegment)
        }
    } finally {
        SegmentPool.recycle(segment)
    }
}
