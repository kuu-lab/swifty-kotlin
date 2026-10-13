@file:OptIn(UnsafeIoApi::class)

import kotlinx.io.*
import kotlinx.io.unsafe.UnsafeBufferOperations
import kotlinx.io.unsafe.withData

private fun fail(): Nothing = throw IllegalStateException("upstream unsafe assertion failed")

private fun assertEquals(expected: Int, actual: Int) {
    if (expected != actual) fail()
}

private fun assertEquals(expected: Long, actual: Long) {
    if (expected != actual) fail()
}

private fun assertEquals(expected: Int, actual: Long) {
    if (expected.toLong() != actual) fail()
}

private fun assertEquals(expected: Long, actual: Int) {
    if (expected != actual.toLong()) fail()
}

private fun assertEquals(expected: Any?, actual: Any?) {
    if (expected != actual) fail()
}

private fun assertTrue(actual: Boolean) {
    if (!actual) fail()
}

private fun assertFalse(actual: Boolean) {
    if (actual) fail()
}

private fun assertNull(actual: Any?) {
    if (actual != null) fail()
}

private fun <T : Any> assertNotNull(actual: T?): T {
    return actual ?: fail()
}

private fun assertArrayEquals(expected: ByteArray, actual: ByteArray) {
    if (!expected.contentEquals(actual)) fail()
}

private fun assertContentEquals(expected: ByteArray, actual: ByteArray) {
    assertArrayEquals(expected, actual)
}

private inline fun <reified T : Throwable> assertFailsWith(block: () -> Unit) {
    var failure: Throwable? = null
    try {
        block()
    } catch (caught: Throwable) {
        failure = caught
    }
    if (failure !is T) fail()
}

private class TestException : RuntimeException()

private fun Buffer.readByteArray(): ByteArray = ByteArray(size.toInt()) { readByte() }

private fun segmentSizes(buffer: Buffer): List<Int> {
    val result = mutableListOf<Int>()
    UnsafeBufferOperations.iterate(buffer) { ctx, head ->
        var segment = head
        while (segment != null) {
            result.add(segment.size)
            segment = ctx.next(segment)
        }
    }
    return result
}

// Port of core/common/test/unsafe/UnsafeBufferOperationsForEachTest.kt.
private object UnsafeBufferOperationsForEachTest {
    fun emptyBuffer() {
        UnsafeBufferOperations.forEachSegment(Buffer()) { _, _ -> fail() }
    }

    fun singleSegment() {
        var counter = 0
        UnsafeBufferOperations.forEachSegment(Buffer().also { it.writeByte(1) }) { _, segment ->
            ++counter
            assertEquals(1, segment.size)
        }
        assertEquals(1, counter)
    }

    fun multipleSegments() {
        val buffer = Buffer()
        val expectedSegments = 10
        for (i in 0 ..< expectedSegments) {
            UnsafeBufferOperations.moveToTail(buffer, byteArrayOf(i.toByte()))
        }

        val storedBytes = ByteArray(expectedSegments)
        var idx = 0
        UnsafeBufferOperations.forEachSegment(buffer) { ctx, segment ->
            assertTrue(idx < expectedSegments)
            storedBytes[idx++] = ctx.getUnchecked(segment, 0)
        }

        assertArrayEquals(ByteArray(expectedSegments) { it.toByte() }, storedBytes)
    }

    fun acquireDataDuringIteration() {
        val buffer = Buffer().also { it.writeString("hello buffer") }
        val expectedSize = buffer.size

        UnsafeBufferOperations.forEachSegment(buffer) { ctx, segment ->
            ctx.withData(segment) { data, startIndex, endIndex ->
                assertEquals("hello buffer", data.decodeToString(startIndex, endIndex))
            }
        }

        assertEquals(expectedSize, buffer.size)
    }
}

// Port of core/common/test/unsafe/UnsafeBufferOperationsIterationTest.kt.
private object UnsafeBufferOperationsIterationTest {
    fun callsInPlaceContract() {
        val buffer = Buffer().also { it.writeString("hello buffer") }

        val called: Boolean
        UnsafeBufferOperations.iterate(buffer) { ctx, segment ->
            called = true
            val withDataCalled: Boolean
            ctx.withData(assertNotNull(segment)) { _, _, _ -> withDataCalled = true }
            assertTrue(withDataCalled)
        }
        assertTrue(called)

        val offsetCalled: Boolean
        UnsafeBufferOperations.iterate(buffer, 1) { ctx, segment, _ ->
            offsetCalled = true
            val withDataCalled: Boolean
            ctx.withData(assertNotNull(segment)) { _, _, _ -> withDataCalled = true }
            assertTrue(withDataCalled)
        }
        assertTrue(offsetCalled)
    }

    fun emptyBuffer() {
        UnsafeBufferOperations.iterate(Buffer()) { _, head -> assertNull(head) }
    }

    fun singleSegment() {
        UnsafeBufferOperations.iterate(Buffer().also { it.writeByte(1) }) { ctx, head ->
            val segment = assertNotNull(head)
            assertEquals(1, segment.size)
            assertNull(ctx.next(segment))
        }
    }

    fun multipleSegments() {
        val buffer = Buffer()
        val expectedSegments = 10
        for (i in 0 ..< expectedSegments) {
            UnsafeBufferOperations.moveToTail(buffer, byteArrayOf(i.toByte()))
        }

        val storedBytes = ByteArray(expectedSegments)
        UnsafeBufferOperations.iterate(buffer) { ctx, head ->
            var idx = 0
            var segment = head
            do {
                val current = assertNotNull(segment)
                assertTrue(idx < expectedSegments)
                storedBytes[idx++] = ctx.getUnchecked(current, 0)
                segment = ctx.next(current)
            } while (segment != null)
        }

        assertArrayEquals(ByteArray(expectedSegments) { it.toByte() }, storedBytes)
    }

    fun acquireDataDuringIteration() {
        val buffer = Buffer().also { it.writeString("hello buffer") }
        val expectedSize = buffer.size

        UnsafeBufferOperations.iterate(buffer) { ctx, head ->
            val segment = assertNotNull(head)
            ctx.withData(segment) { data, startIndex, endIndex ->
                assertEquals("hello buffer", data.decodeToString(startIndex, endIndex))
            }
        }

        assertEquals(expectedSize, buffer.size)
    }

    fun seekStartOffsets() {
        val firstSegmentData = "hello buffer".encodeToByteArray()
        val buffer = Buffer().also { it.write(firstSegmentData) }

        UnsafeBufferOperations.iterate(buffer, offset = 6) { _, segment, offset ->
            assertNotNull(segment)
            assertEquals(0L, offset)
        }

        val secondSegmentData = "; that's a second segment".encodeToByteArray()
        UnsafeBufferOperations.moveToTail(buffer, secondSegmentData)
        val thirdSegmentData = "; that's a third segment".encodeToByteArray()
        UnsafeBufferOperations.moveToTail(buffer, thirdSegmentData)

        val startOfSegmentOffsets = longArrayOf(
            0,
            firstSegmentData.size.toLong(),
            (firstSegmentData.size + secondSegmentData.size).toLong(),
            (firstSegmentData.size + secondSegmentData.size + thirdSegmentData.size).toLong()
        )
        val segmentsData = arrayOf(firstSegmentData, secondSegmentData, thirdSegmentData)

        for (limitIdx in 1 ..< startOfSegmentOffsets.size) {
            val startOffset = startOfSegmentOffsets[limitIdx - 1]
            val limitOffset = startOfSegmentOffsets[limitIdx]
            for (offset in startOffset ..< limitOffset) {
                UnsafeBufferOperations.iterate(buffer, offset) { ctx, segment, segmentOffset ->
                    val current = assertNotNull(segment)
                    assertEquals(startOffset, segmentOffset)
                    ctx.withData(current) { data, startIndex, endIndex ->
                        val slice = data.sliceArray(startIndex ..< endIndex)
                        assertArrayEquals(segmentsData[limitIdx - 1], slice)
                    }
                }
            }
        }
    }

    fun seekOutOfBounds() {
        assertFailsWith<IllegalArgumentException> {
            UnsafeBufferOperations.iterate(Buffer(), offset = -1) { _, _, _ -> fail() }
        }
        assertFailsWith<IndexOutOfBoundsException> {
            UnsafeBufferOperations.iterate(Buffer(), offset = 0) { _, _, _ -> fail() }
        }
        assertFailsWith<IndexOutOfBoundsException> {
            UnsafeBufferOperations.iterate(Buffer(), offset = 9001) { _, _, _ -> fail() }
        }

        val buffer = Buffer().also { it.writeInt(42) }
        assertFailsWith<IllegalArgumentException> {
            UnsafeBufferOperations.iterate(buffer, offset = -1) { _, _, _ -> fail() }
        }
        assertFailsWith<IndexOutOfBoundsException> {
            UnsafeBufferOperations.iterate(buffer, offset = 4) { _, _, _ -> fail() }
        }
    }
}

// Port of core/common/test/unsafe/UnsafeBufferOperationsMoveTest.kt.
private object UnsafeBufferOperationsMoveTest {
    fun moveArrayFully() {
        val buffer = Buffer()
        val data = "hello unsafe new world!".encodeToByteArray()
        UnsafeBufferOperations.moveToTail(buffer, data)
        assertFalse(buffer.exhausted())
        assertEquals(data.size.toLong(), buffer.size)
        assertEquals("hello unsafe new world!", buffer.readString())
    }

    fun moveArraySlice() {
        val buffer = Buffer()
        val data = "hello unsafe new world!".encodeToByteArray()
        UnsafeBufferOperations.moveToTail(buffer, data, 6, 12)
        assertEquals(6L, buffer.size)
        assertEquals("unsafe", buffer.readString())
    }

    fun movedArrayIsReadOnly() {
        val firstBuffer = Buffer().also { it.writeString("this is ") }
        val secondBuffer = Buffer().also { it.writeString("this is ") }
        val data = "first second third".encodeToByteArray()

        UnsafeBufferOperations.moveToTail(firstBuffer, data, 0, 5)
        firstBuffer.writeString(" buffer")
        UnsafeBufferOperations.moveToTail(secondBuffer, data, 6, 12)
        secondBuffer.writeString(" buffer")

        assertArrayEquals("first second third".encodeToByteArray(), data)
        assertEquals("this is first buffer", firstBuffer.readString())
        assertEquals("this is second buffer", secondBuffer.readString())
    }

    fun moveEmptySlice() {
        val buffer = Buffer()
        UnsafeBufferOperations.moveToTail(buffer, ByteArray(0))
        assertTrue(buffer.exhausted())
        UnsafeBufferOperations.moveToTail(buffer, ByteArray(10), 5, 5)
        assertTrue(buffer.exhausted())
    }

    fun illegalArgumentsHandling() {
        assertFailsWith<IndexOutOfBoundsException> {
            UnsafeBufferOperations.moveToTail(Buffer(), byteArrayOf(1), -1)
        }
        assertFailsWith<IllegalArgumentException> {
            UnsafeBufferOperations.moveToTail(Buffer(), ByteArray(10), 2, 0)
        }
        assertFailsWith<IndexOutOfBoundsException> {
            UnsafeBufferOperations.moveToTail(Buffer(), ByteArray(10), 11, 12)
        }
    }

    fun moveMultipleSegments() {
        val buffer = Buffer()
        val segmentsCount = 10
        for (i in 0 ..< segmentsCount) {
            UnsafeBufferOperations.moveToTail(buffer, byteArrayOf(i.toByte()))
        }
        assertEquals(10, buffer.size)
        assertEquals(listOf(1, 1, 1, 1, 1, 1, 1, 1, 1, 1), segmentSizes(buffer))
        assertContentEquals(ByteArray(segmentsCount) { it.toByte() }, buffer.readByteArray())
    }
}

// Port of core/common/test/unsafe/UnsafeBufferOperationsReadTest.kt.
private object UnsafeBufferOperationsReadTest {
    fun callsInPlaceContract() {
        val buffer = Buffer().apply { writeString("hello world") }

        val bytesCalled: Boolean
        UnsafeBufferOperations.readFromHead(buffer) { _, _, _ ->
            bytesCalled = true
            0
        }.also { assertEquals(0, it) }
        assertTrue(bytesCalled)

        val segmentsCalled: Boolean
        UnsafeBufferOperations.readFromHead(buffer) { _, _ ->
            segmentsCalled = true
            0
        }.also { assertEquals(0, it) }
        assertTrue(segmentsCalled)
    }

    fun bufferCapacity() {
        val buffer = Buffer().apply { writeString("hello world") }
        val expectedReadableSize = buffer.size.toInt()
        UnsafeBufferOperations.readFromHead(buffer) { data, startIndex, endIndex ->
            assertTrue(endIndex <= data.size)
            assertEquals(0, startIndex)
            assertEquals(expectedReadableSize, endIndex - startIndex)
            0
        }.also { assertEquals(0, it) }
    }

    fun consumeByteByByte() {
        val expectedData = "hello world".encodeToByteArray()
        val actualData = ByteArray(expectedData.size)
        val buffer = Buffer().apply { write(expectedData) }
        for (idx in actualData.indices) {
            val read = UnsafeBufferOperations.readFromHead(buffer) { data, startIndex, _ ->
                actualData[idx] = data[startIndex]
                1
            }
            assertEquals(1, read)
            assertEquals(actualData.size - idx - 1, buffer.size.toInt())
        }
        assertTrue(buffer.exhausted())
        assertArrayEquals(expectedData, actualData)
    }

    fun readNothing() {
        val buffer = Buffer().apply { writeInt(42) }
        val read1 = UnsafeBufferOperations.readFromHead(buffer) { _, _, _ -> 0 }
        assertEquals(0, read1)
        assertEquals(42, buffer.readInt())

        buffer.writeInt(42)
        val read2 = UnsafeBufferOperations.readFromHead(buffer) { _, _ -> 0 }
        assertEquals(0, read2)
        assertEquals(42, buffer.readInt())
    }

    fun readEverything() {
        val buffer = Buffer().also { it.writeString("hello world") }
        val read1 = UnsafeBufferOperations.readFromHead(buffer) { _, startIndex, endIndex ->
            endIndex - startIndex
        }
        assertEquals(11, read1)
        assertTrue(buffer.exhausted())

        buffer.writeString("hello world")
        val read2 = UnsafeBufferOperations.readFromHead(buffer) { _, segment -> segment.size }
        assertEquals(11, read2)
        assertTrue(buffer.exhausted())
    }

    fun readFromEmptyBuffer() {
        val buffer = Buffer()
        assertFailsWith<IllegalArgumentException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, _, _ -> fail() }
        }
        assertFailsWith<IllegalArgumentException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, _ -> fail() }
        }
    }

    fun readFromTheSegmentEnd() {
        val segmentSize = UnsafeBufferOperations.maxSafeWriteCapacity
        val extraBytesCount = 128
        val bytesToSkip = segmentSize - 2
        val buffer = Buffer().apply { write(ByteArray(segmentSize + extraBytesCount) { 0xff.toByte() }) }
        buffer.skip(bytesToSkip.toLong())

        UnsafeBufferOperations.readFromHead(buffer) { _, startIndex, endIndex ->
            assertEquals(bytesToSkip, startIndex)
            assertEquals(2, endIndex - startIndex)
            2
        }.also { assertEquals(2, it) }

        assertEquals(extraBytesCount, buffer.size.toInt())
    }

    fun readFromTheSegmentEndUsingCtx() {
        val segmentSize = UnsafeBufferOperations.maxSafeWriteCapacity
        val extraBytesCount = 128
        val bytesToSkip = segmentSize - 2
        val buffer = Buffer().apply { write(ByteArray(segmentSize + extraBytesCount) { 0xff.toByte() }) }
        buffer.skip(bytesToSkip.toLong())

        UnsafeBufferOperations.readFromHead(buffer) { ctx, segment ->
            assertEquals(2, segment.size)
            ctx.withData(segment) { _, startIndex, endIndex ->
                assertEquals(bytesToSkip, startIndex)
                assertEquals(2, endIndex - startIndex)
            }
            2
        }.also { assertEquals(2, it) }

        assertEquals(extraBytesCount, buffer.size.toInt())
    }

    fun returnIllegalReadCount() {
        val buffer = Buffer().apply { writeInt(0) }
        assertFailsWith<IllegalStateException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, _, _ -> -1 }
        }
        assertEquals(4L, buffer.size)
        assertFailsWith<IllegalStateException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, _ -> -1 }
        }
        assertEquals(4L, buffer.size)
        assertFailsWith<IllegalStateException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, from, to -> to - from + 1 }
        }
        assertEquals(4L, buffer.size)
        assertFailsWith<IllegalStateException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, segment -> segment.remainingCapacity + 1 }
        }
        assertEquals(4L, buffer.size)
    }

    fun resetReadOnException() {
        val buffer = Buffer().apply { writeString("hello world") }
        val sizeBeforeRead = buffer.size
        assertFailsWith<TestException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, _, _ -> throw TestException() }
        }
        assertEquals(sizeBeforeRead, buffer.size)
        assertFailsWith<TestException> {
            UnsafeBufferOperations.readFromHead(buffer) { _, _ -> throw TestException() }
        }
        assertEquals(sizeBeforeRead, buffer.size)
    }
}

// Port of core/common/test/unsafe/UnsafeBufferOperationsWriteTest.kt.
private object UnsafeBufferOperationsWriteTest {
    fun callsInPlaceContract() {
        val bytesCalled: Boolean
        UnsafeBufferOperations.writeToTail(Buffer(), 1) { _, _, _ ->
            bytesCalled = true
            0
        }.also { assertEquals(0, it) }
        assertTrue(bytesCalled)

        val segmentsCalled: Boolean
        UnsafeBufferOperations.writeToTail(Buffer(), 1) { _, _ ->
            segmentsCalled = true
            0
        }.also { assertEquals(0, it) }
        assertTrue(segmentsCalled)
    }

    fun bufferCapacity() {
        val buffer = Buffer()
        val expectedCapacity = UnsafeBufferOperations.maxSafeWriteCapacity
        UnsafeBufferOperations.writeToTail(buffer, 1) { data, startIndex, endIndex ->
            assertEquals(expectedCapacity, data.size)
            assertEquals(0, startIndex)
            assertEquals(expectedCapacity, endIndex - startIndex)
            assertEquals(0L, buffer.size)
            0
        }.also { assertEquals(0, it) }

        UnsafeBufferOperations.writeToTail(buffer, 1) { _, segment ->
            assertEquals(expectedCapacity, segment.remainingCapacity)
            assertEquals(0, segment.size)
            assertEquals(0L, buffer.size)
            0
        }.also { assertEquals(0, it) }
    }

    fun writeByteByByte() {
        val buffer = Buffer()
        val data = "hello world".encodeToByteArray()
        for (idx in data.indices) {
            val written = UnsafeBufferOperations.writeToTail(buffer, 1) { writable, pos, _ ->
                writable[pos] = data[idx]
                1
            }
            assertEquals(1, written)
            assertEquals(idx + 1, buffer.size.toInt())
        }
        assertEquals("hello world", buffer.readString())
    }

    fun writeNothing() {
        val buffer = Buffer()
        val write1 = UnsafeBufferOperations.writeToTail(buffer, 1) { _, _, _ -> 0 }
        assertEquals(0, write1)
        assertTrue(buffer.exhausted())
        val write2 = UnsafeBufferOperations.writeToTail(buffer, 1) { _, _ -> 0 }
        assertEquals(0, write2)
        assertTrue(buffer.exhausted())

        buffer.writeInt(42)
        UnsafeBufferOperations.writeToTail(buffer, 1) { _, _, _ -> 0 }.also { assertEquals(0, it) }
        assertEquals(4, buffer.size)
        UnsafeBufferOperations.writeToTail(buffer, 1) { _, _ -> 0 }.also { assertEquals(0, it) }
        assertEquals(4, buffer.size)

        val maxWriteCapacity = UnsafeBufferOperations.maxSafeWriteCapacity
        buffer.write(ByteArray(maxWriteCapacity - 4))
        UnsafeBufferOperations.writeToTail(buffer, 1) { _, _, _ -> 0 }.also { assertEquals(0, it) }
        assertEquals(maxWriteCapacity.toLong(), buffer.size)
        UnsafeBufferOperations.writeToTail(buffer, 1) { _, _ -> 0 }.also { assertEquals(0, it) }
        assertEquals(maxWriteCapacity.toLong(), buffer.size)
    }

    fun writeWholeBuffer() {
        val buffer = Buffer()
        val written = UnsafeBufferOperations.writeToTail(buffer, 1) { data, from, to ->
            for (idx in from ..< to) data[idx] = 42
            to - from
        }
        val maxWriteCapacity = UnsafeBufferOperations.maxSafeWriteCapacity
        assertEquals(maxWriteCapacity, written)
        assertEquals(maxWriteCapacity, buffer.size.toInt())
        assertArrayEquals(ByteArray(maxWriteCapacity) { 42 }, buffer.readByteArray())
    }

    fun writeWithCtx() {
        val buffer = Buffer()
        val written = UnsafeBufferOperations.writeToTail(buffer, 1) { ctx, segment ->
            ctx.setUnchecked(segment, 0, 1)
            ctx.setUnchecked(segment, 1, 2)
            2
        }
        assertEquals(2, written)
        assertArrayEquals(byteArrayOf(1, 2), buffer.readByteArray())
    }

    fun requireToManyBytes() {
        val buffer = Buffer()
        assertFailsWith<IllegalArgumentException> {
            UnsafeBufferOperations.writeToTail(buffer, 100500) { _, _, _ -> fail() }
        }
        assertTrue(buffer.exhausted())
        assertFailsWith<IllegalArgumentException> {
            UnsafeBufferOperations.writeToTail(buffer, 100500) { _, _ -> fail() }
        }
        assertTrue(buffer.exhausted())
    }

    fun writeToTheEndOfABuffer() {
        val maxWriteCapacity = UnsafeBufferOperations.maxSafeWriteCapacity
        val buffer = Buffer().apply { write(ByteArray(maxWriteCapacity - 1)) }
        UnsafeBufferOperations.writeToTail(buffer, 1) { data, pos, limit ->
            assertEquals(1, limit - pos)
            data[pos] = 42
            1
        }.also { assertEquals(1, it) }
        assertEquals(maxWriteCapacity, buffer.size.toInt())
        UnsafeBufferOperations.writeToTail(buffer, 1) { data, pos, _ ->
            data[pos] = 43
            1
        }.also { assertEquals(1, it) }
        assertEquals(maxWriteCapacity + 1, buffer.size.toInt())
        buffer.skip(maxWriteCapacity - 1L)
        assertArrayEquals(byteArrayOf(42, 43), buffer.readByteArray())
    }

    fun writeToTheEndOfABufferUsingCtx() {
        val maxWriteCapacity = UnsafeBufferOperations.maxSafeWriteCapacity
        val buffer = Buffer().apply { write(ByteArray(maxWriteCapacity - 1)) }
        UnsafeBufferOperations.writeToTail(buffer, 1) { ctx, segment ->
            assertEquals(1, segment.remainingCapacity)
            ctx.setUnchecked(segment, 0, 42)
            1
        }.also { assertEquals(1, it) }
        assertEquals(maxWriteCapacity, buffer.size.toInt())
        UnsafeBufferOperations.writeToTail(buffer, 1) { ctx, segment ->
            ctx.setUnchecked(segment, 0, 43)
            1
        }.also { assertEquals(1, it) }
        assertEquals(maxWriteCapacity + 1, buffer.size.toInt())
        buffer.skip(maxWriteCapacity - 1L)
        assertArrayEquals(byteArrayOf(42, 43), buffer.readByteArray())
    }

    fun returnIllegalWriteCount() {
        val buffer = Buffer()
        assertFailsWith<IllegalStateException> {
            UnsafeBufferOperations.writeToTail(buffer, 1) { _, _, _ -> -1 }
        }
        assertTrue(buffer.exhausted())
        assertFailsWith<IllegalStateException> {
            UnsafeBufferOperations.writeToTail(buffer, 1) { _, _, _ -> 100500 }
        }
        assertTrue(buffer.exhausted())
    }

    fun writeMultipleBytes() {
        val buffer = Buffer()
        UnsafeBufferOperations.writeToTail(buffer, 10) { ctx, tail ->
            ctx.setUnchecked(tail, 0, 1)
            ctx.setUnchecked(tail, 1, 2, 3)
            ctx.setUnchecked(tail, 3, 4, 5, 6)
            ctx.setUnchecked(tail, 6, 7, 8, 9, 10)
            10
        }.also { assertEquals(10, it) }
        assertArrayEquals(ByteArray(10) { (it + 1).toByte() }, buffer.readByteArray())

        UnsafeBufferOperations.writeToTail(buffer, 4) { ctx, tail ->
            ctx.setUnchecked(tail, 0, 11, 11, 11, 11)
            ctx.setUnchecked(tail, 1, 10, 10, 10)
            ctx.setUnchecked(tail, 2, 9, 9)
            ctx.setUnchecked(tail, 3, 8)
            4
        }.also { assertEquals(4, it) }
        assertArrayEquals(byteArrayOf(11, 10, 9, 8), buffer.readByteArray())
    }

    fun resetWriteOnException() {
        val buffer = Buffer()
        assertFailsWith<TestException> {
            UnsafeBufferOperations.writeToTail(buffer, 2) { _, _, _ -> throw TestException() }
        }
        assertTrue(buffer.exhausted())
        assertFailsWith<TestException> {
            UnsafeBufferOperations.writeToTail(buffer, 2) { _, _ -> throw TestException() }
        }
        assertTrue(buffer.exhausted())
    }

    fun returnLessBytesThanItWasActuallyWritten() {
        val buffer = Buffer()
        UnsafeBufferOperations.writeToTail(buffer, 42) { data, pos, limit ->
            data.fill(0xab.toByte(), pos, limit)
            4
        }.also { assertEquals(4, it) }
        assertEquals(4, buffer.size)
        assertEquals(0xababababu, buffer.readUInt())
    }
}

fun main() {
    UnsafeBufferOperationsForEachTest.emptyBuffer()
    UnsafeBufferOperationsForEachTest.singleSegment()
    UnsafeBufferOperationsForEachTest.multipleSegments()
    UnsafeBufferOperationsForEachTest.acquireDataDuringIteration()
    println("forEach:pass")

    UnsafeBufferOperationsIterationTest.callsInPlaceContract()
    UnsafeBufferOperationsIterationTest.emptyBuffer()
    UnsafeBufferOperationsIterationTest.singleSegment()
    UnsafeBufferOperationsIterationTest.multipleSegments()
    UnsafeBufferOperationsIterationTest.acquireDataDuringIteration()
    UnsafeBufferOperationsIterationTest.seekStartOffsets()
    UnsafeBufferOperationsIterationTest.seekOutOfBounds()
    println("iteration:pass")

    UnsafeBufferOperationsMoveTest.moveArrayFully()
    UnsafeBufferOperationsMoveTest.moveArraySlice()
    UnsafeBufferOperationsMoveTest.movedArrayIsReadOnly()
    UnsafeBufferOperationsMoveTest.moveEmptySlice()
    UnsafeBufferOperationsMoveTest.illegalArgumentsHandling()
    UnsafeBufferOperationsMoveTest.moveMultipleSegments()
    println("move:pass")

    UnsafeBufferOperationsReadTest.callsInPlaceContract()
    UnsafeBufferOperationsReadTest.bufferCapacity()
    UnsafeBufferOperationsReadTest.consumeByteByByte()
    UnsafeBufferOperationsReadTest.readNothing()
    UnsafeBufferOperationsReadTest.readEverything()
    UnsafeBufferOperationsReadTest.readFromEmptyBuffer()
    UnsafeBufferOperationsReadTest.readFromTheSegmentEnd()
    UnsafeBufferOperationsReadTest.readFromTheSegmentEndUsingCtx()
    UnsafeBufferOperationsReadTest.returnIllegalReadCount()
    UnsafeBufferOperationsReadTest.resetReadOnException()
    println("read:pass")

    UnsafeBufferOperationsWriteTest.callsInPlaceContract()
    UnsafeBufferOperationsWriteTest.bufferCapacity()
    UnsafeBufferOperationsWriteTest.writeByteByByte()
    UnsafeBufferOperationsWriteTest.writeNothing()
    UnsafeBufferOperationsWriteTest.writeWholeBuffer()
    UnsafeBufferOperationsWriteTest.writeWithCtx()
    UnsafeBufferOperationsWriteTest.requireToManyBytes()
    UnsafeBufferOperationsWriteTest.writeToTheEndOfABuffer()
    UnsafeBufferOperationsWriteTest.writeToTheEndOfABufferUsingCtx()
    UnsafeBufferOperationsWriteTest.returnIllegalWriteCount()
    UnsafeBufferOperationsWriteTest.writeMultipleBytes()
    UnsafeBufferOperationsWriteTest.resetWriteOnException()
    UnsafeBufferOperationsWriteTest.returnLessBytesThanItWasActuallyWritten()
    println("write:pass")
}
