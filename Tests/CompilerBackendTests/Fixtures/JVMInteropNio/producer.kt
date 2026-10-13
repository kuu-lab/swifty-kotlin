@file:OptIn(kotlinx.io.InternalIoApi::class, kotlinx.io.UnsafeIoApi::class, kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)
import java.io.ByteArrayOutputStream
import java.nio.charset.IllegalCharsetNameException
import java.nio.charset.UnsupportedCharsetException
import java.io.InputStream
import java.io.ByteArrayInputStream
import java.io.OutputStream
import java.io.IOException
import java.io.SequenceInputStream
import java.io.EOFException
import java.io.FileNotFoundException
import java.nio.charset.Charset
import kotlinx.io.unsafe.*
import java.nio.ByteBuffer
import java.nio.BufferOverflowException
import java.nio.BufferUnderflowException
import java.nio.ReadOnlyBufferException
import java.nio.InvalidMarkException
import kotlinx.io.*
import kotlinx.io.bytestring.*
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

private fun failure(block: () -> Unit): String = try { block(); "none" } catch (e: Exception) {
    when (e) {
        is ReadOnlyBufferException -> "ReadOnly"
        is BufferOverflowException -> "Overflow"
        is BufferUnderflowException -> "Underflow"
        is IndexOutOfBoundsException -> "Bounds"
        is IllegalArgumentException -> "Argument"
        is IOException -> "IO"
        else -> throw e
    }
}
public fun runNioInteropProbe() {
    val b = ByteBuffer.wrap(byteArrayOf(1, 2, 3, 4)).position(1).limit(3)
    println("relative-default:${b.getByteString().size}/${b.position()}")
    b.position(1)
    println("absolute:${b.getByteString(1, 1)[0]}/${b.position()}")
    println("relative-invalid:${failure { b.getByteString(3) }}/${b.position()}")
    println("absolute-at-limit-zero:${failure { b.getByteString(3, 0) }}/${b.position()}")
    println("position-invalid:${failure { b.position(-1) }}/${b.position()}")
    println("limit-invalid:${failure { b.limit(5) }}/${b.limit()}")
    b.position(3)
    println("underflow:${failure { b.get() }}/${b.position()}")
    println("overflow:${failure { b.put(9.toByte()) }}/${b.position()}")
    val ro = b.asReadOnlyBuffer()
    val one = ByteString(byteArrayOf(9))
    println("readonly-relative-before-overflow:${failure { ro.putByteString(one) }}/${ro.position()}")
    println("readonly-absolute-bounds-first:${failure { ro.putByteString(3, one) }}/${ro.position()}")
    println("readonly-absolute-empty:${failure { ro.putByteString(1, ByteString()) }}/${ro.position()}")
    val immutable = ByteString(byteArrayOf(5, 6))
    val view = immutable.asReadOnlyByteBuffer()
    UnsafeByteStringOperations.withByteArrayUnsafe(immutable) { it[0] = 8 }
    println("readonly-shared:${view.get(0)}/${view.isReadOnly()}/${view.hasArray()}")
    val backing = byteArrayOf(10, 20, 30, 40)
    val sliced = ByteBuffer.wrap(backing).position(1).limit(3).slice()
    sliced.put(0, 7.toByte())
    println("slice-shared:${backing[1]}/${sliced.capacity()}/${sliced.arrayOffset()}")

    val channelBuffer = Buffer().apply { write(byteArrayOf(1, 2, 3)) }
    val channel = channelBuffer.asByteChannel()
    val dst = ByteBuffer.allocate(2)
    println("buffer-channel-read:${channel.read(dst)}/${dst.position()}/${channelBuffer.size}")
    channel.close()
    println("buffer-channel-close-noop:${channel.isOpen()}")
    val exhausted = Buffer()
    println("buffer-read-empty:${exhausted.readAtMostTo(ByteBuffer.allocate(0))}")

    val getArray = byteArrayOf(1, 2, 3, 4, 5)
    val get = ByteBuffer.wrap(getArray)
    get.get(getArray, 2, 3)
    println("get-overlap:${getArray.joinToString()}/${get.position()}")
    val putArray = byteArrayOf(1, 2, 3, 4, 5)
    val put = ByteBuffer.wrap(putArray).position(2)
    put.put(putArray, 0, 3)
    println("put-overlap:${putArray.joinToString()}/${put.position()}")
    val original = ByteBuffer.wrap(byteArrayOf(1, 2, 3)).position(1)
    val duplicate = original.duplicate().position(0)
    duplicate.put(9.toByte())
    println("duplicate-shared-independent:${original.get(0)}/${original.position()}/${duplicate.position()}")
    original.position(2).mark().limit(1)
    val mark = try { original.reset(); "none" } catch (e: InvalidMarkException) { "InvalidMark" }
    println("limit-invalidates-mark:$mark/${original.position()}/${original.limit()}")
    val direct = ByteBuffer.allocateDirect(2)
    val array = try { direct.array(); "none" } catch (e: UnsupportedOperationException) { "Unsupported" }
    println("direct-hidden-array:${direct.isDirect()}/${direct.hasArray()}/$array")
    val wrap = ByteBuffer.wrap(byteArrayOf(1, 2, 3, 4, 5), 2, 2)
    println("wrap-offset:${wrap.capacity()}/${wrap.position()}/${wrap.limit()}/${wrap.arrayOffset()}")
}

private fun closed(block: () -> Unit): String = try { block(); "none" } catch (e: IllegalStateException) { "State" }

public fun runNioClosureProbe() {
    val storage = byteArrayOf(0, 0, 0, 0)
    val put = ByteBuffer.wrap(storage).position(1)
    put.putByteString(ByteString(byteArrayOf(7, 8)))
    println("relative-put-success:${storage.joinToString()}/${put.position()}")
    put.putByteString(0, ByteString(byteArrayOf(5)))
    println("absolute-put-success:${storage.joinToString()}/${put.position()}")
    val transfer = ByteBuffer.wrap(byteArrayOf(1, 2, 3, 4)).position(2)
    val transferred = Buffer().transferFrom(transfer)
    println("buffer-transfer:${transfer.position()}/${transferred.readByteArray().joinToString()}")
    val written = Buffer()
    val bufferChannel = written.asByteChannel()
    bufferChannel.close()
    val incoming = ByteBuffer.wrap(byteArrayOf(6, 7))
    println("buffer-channel-write-after-close:${bufferChannel.write(incoming)}/${incoming.position()}/${written.size}")

    val raw: RawSource = Buffer().apply { write(byteArrayOf(1, 2)) }
    val source = raw.buffered()
    val channel = source.asByteChannel()
    println("source-channel-open:${channel.isOpen()}")
    val first = ByteBuffer.allocate(1)
    println("source-buffer-read:${source.readAtMostTo(first)}/${first.position()}/${source.buffer.size}")
    val second = ByteBuffer.allocate(1)
    println("source-channel-read:${channel.read(second)}/${second.get(0)}")
    channel.close()
    println("source-channel-close:${channel.isOpen()}/${closed { channel.read(ByteBuffer.allocate(1)) }}")

    val target = Buffer()
    val rawSink: RawSink = target
    val sink = rawSink.buffered()
    val sinkChannel = sink.asByteChannel()
    val firstWrite = ByteBuffer.wrap(byteArrayOf(10))
    val firstCount = sink.write(firstWrite)
    sink.flush()
    println("sink-buffer-write:$firstCount/${firstWrite.position()}/${target.readByte()}")
    val secondWrite = ByteBuffer.wrap(byteArrayOf(11))
    val secondCount = sinkChannel.write(secondWrite)
    sink.flush()
    println("sink-channel-write:$secondCount/${secondWrite.position()}/${target.readByte()}")
    sinkChannel.close()
    println("sink-channel-close:${sinkChannel.isOpen()}/${closed { sinkChannel.write(ByteBuffer.allocate(1)) }}")
}

private fun sharedFailure(block: () -> Unit): String = try { block(); "none" } catch (e: Exception) {
    when (e) {
        is ReadOnlyBufferException -> "ReadOnly"
        is EOFException -> "EOF"
        is IOException -> "IO"
        is IndexOutOfBoundsException -> "Bounds"
        is IllegalArgumentException -> "Argument"
        is IllegalStateException -> "State"
        else -> throw e
    }
}

public fun runSharedInteropProbe() {
    var reads = 0
    var closes = 0
    var next = 0
    val raw = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
            reads++
            if (next == 3) return -1L
            sink.writeByte((next++ + 253).toByte())
            return 1L
        }
        override fun close() { closes++ }
    }
    val source = raw.buffered()
    val input = source.asInputStream()
    println("lazy-create:$reads/${input.available()}")
    println("lazy-read:${input.read()}/$reads/${input.available()}")
    val bytes = byteArrayOf(9, 9, 9, 9)
    println("lazy-bulk:${input.read(bytes, 1, 2)}/${bytes.joinToString()}/$reads")
    println("raw-short:${input.asSource().readAtMostTo(Buffer(), 9)}/$reads")
    println("bulk-eof:${input.read(bytes, 0, 2)}/$reads")
    println("zero-range:${input.read(bytes, 4, 0)}/$reads")
    println("invalid-range:${sharedFailure { input.read(bytes, -1, 1) }}/$reads")
    println("input-mark:${input.markSupported()}/${sharedFailure { input.reset() }}")
    input.close()
    println("input-close:$closes/${sharedFailure { input.read() }}/${sharedFailure { input.available() }}")
    println("closed-before-bounds:${sharedFailure { input.read(bytes, -1, 1) }}")
    val identity = IOException("identity")
    val brokenSource = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = throw identity
        override fun close() { throw identity }
    }.buffered().asInputStream()
    val sameRead = try { brokenSource.read(); false } catch (e: IOException) { e === identity }
    val sameClose = try { brokenSource.close(); false } catch (e: IOException) { e === identity }
    println("input-exception-identity:$sameRead/$sameClose")

    val buffer = Buffer()
    val output = buffer.asOutputStream()
    output.write(byteArrayOf(1, 2, 3, 4), 1, 2)
    output.close()
    output.write(255)
    println("buffer-output-after-close:${buffer.readByteArray().joinToString()}")
    println("output-range-invalid:${sharedFailure { output.write(bytes, -1, 1) }}/${buffer.size}")
    val target = Buffer()
    val sink = (target as RawSink).buffered()
    val realOutput = sink.asOutputStream()
    realOutput.write(byteArrayOf(4, 5, 6), 1, 2)
    realOutput.flush()
    println("output-range:${target.readByteArray().joinToString()}")
    realOutput.close()
    println("output-closed:${sharedFailure { realOutput.write(bytes, -1, 1) }}/${sharedFailure { realOutput.flush() }}")
    val brokenSink = object : RawSink {
        override fun write(source: Buffer, byteCount: Long) { throw identity }
        override fun flush() { throw identity }
        override fun close() { throw identity }
    }.buffered().asOutputStream()
    val pending = Buffer().apply { write(ByteArray(8192) { 7 }) }
    val sameWrite = try { brokenSink.asSink().write(pending, pending.size); false } catch (e: IOException) { e === identity }
    val sameSinkClose = try { brokenSink.close(); false } catch (e: IOException) { e === identity }
    println("output-failed-transaction:$sameWrite/${pending.size}/$sameSinkClose")

    val charset: Charset = Charsets.ISO_8859_1
    val string = "é".encodeToByteString(charset)
    println("charset-canonical:${charset.name()}/${string[0]}/${string.decodeToString(charset)}")
    val text = Buffer()
    text.writeString("aéb", charset, 1, 2)
    println("charset-range:${text.size}/${text.readString(1L, charset)}")
    println("charset-write-bounds:${sharedFailure { text.writeString("abc", charset, -1, 0) }}/${sharedFailure { text.writeString("abc", charset, 2, 1) }}/${text.size}")
    println("charset-read-bounds:${sharedFailure { text.readString(-1L, charset) }}/${sharedFailure { text.readString(1L, charset) }}")
    println("charset-whole-empty:${text.readString(charset).length}")
    println("charset-utf8:${"é".encodeToByteString(Charsets.UTF_8).size}/${byteArrayOf(-61, -87).toString(Charsets.UTF_8)}")
    val io: kotlinx.io.IOException = IOException("x")
    val eof: kotlinx.io.EOFException = EOFException("x")
    val missing: kotlinx.io.files.FileNotFoundException = FileNotFoundException("x")
    println("exception-aliases:${io.message}/${eof is IOException}/${missing is IOException}")

    val head = Buffer().apply { write(byteArrayOf(1, 2, 3)) }
    var calls = 0
    val consumed = UnsafeBufferOperations.readFromHead(head) { bb: ByteBuffer ->
        calls++
        println("unsafe-head-view:${bb.capacity()}/${bb.position()}/${bb.isReadOnly()}/${bb.get(0)}")
        bb.position(2)
    }
    println("unsafe-head-commit:$calls/$consumed/${head.size}/${head.readByte()}")
    head.write(byteArrayOf(4, 5))
    println("unsafe-head-rollback:${sharedFailure { UnsafeBufferOperations.readFromHead(head) { bb: ByteBuffer -> bb.get(); throw identity } }}/${head.size}/${head.readByte()}")
    println("unsafe-head-readonly:${sharedFailure { UnsafeBufferOperations.readFromHead(head) { bb: ByteBuffer -> bb.put(0, 9.toByte()) } }}/${head.size}")
    val tail = Buffer()
    val written = UnsafeBufferOperations.writeToTail(tail, 2) { bb: ByteBuffer -> bb.put(7.toByte()).put(8.toByte()) }
    println("unsafe-tail-commit:$written/${tail.readByteArray().joinToString()}")
    println("unsafe-tail-rollback:${sharedFailure { UnsafeBufferOperations.writeToTail(tail, 1) { bb: ByteBuffer -> bb.put(9.toByte()); throw identity } }}/${tail.size}")
    val bulk = Buffer().apply { write(ByteArray(8193) { (it % 127).toByte() }) }
    val iovec = arrayOfNulls<ByteBuffer>(2)
    val bulkRead = UnsafeBufferOperations.readBulk(bulk, iovec) { vectors, count ->
        println("unsafe-iovec:$count/${vectors[0]!!.isReadOnly()}/${vectors[0]!!.remaining()}/${vectors[1]!!.remaining()}")
        8193L
    }
    println("unsafe-bulk-commit:$bulkRead/${bulk.size}")
    bulk.writeByte(1)
    println("unsafe-bulk-invalid:${sharedFailure { UnsafeBufferOperations.readBulk(bulk, iovec) { _, _ -> 2L } }}/${bulk.size}")
    println("unsafe-bulk-rollback:${sharedFailure { UnsafeBufferOperations.readBulk(bulk, iovec) { _, _ -> throw identity } }}/${bulk.size}")
    println("unsafe-bulk-empty-iovec:${sharedFailure { UnsafeBufferOperations.readBulk(bulk, arrayOfNulls<ByteBuffer>(0)) { _, _ -> 0L } }}/${bulk.size}")
    val empty = Buffer()
    var emptyCalls = 0
    println("unsafe-head-empty:${sharedFailure { UnsafeBufferOperations.readFromHead(empty) { _: ByteBuffer -> emptyCalls++ } }}/$emptyCalls")
}


private fun bufferFailure(block: () -> Unit): String = try { block(); "none" } catch (e: Exception) {
    when (e) {
        is EOFException -> "EOF"
        is IOException -> "IO"
        is IndexOutOfBoundsException -> "Bounds"
        is IllegalArgumentException -> "Argument"
        else -> throw e
    }
}

public fun runBufferCharsetClosureProbe() {
    val input = ByteArrayInputStream(byteArrayOf(1, 2, 3))
    val buffer = Buffer()
    println("stream-transfer:${buffer.transferFrom(input) === buffer}/${buffer.readByteArray().joinToString()}/${input.read()}")
    val partial = ByteArrayInputStream(byteArrayOf(4, 5, 6))
    println("stream-write-count:${buffer.write(partial, 2L) === buffer}/${buffer.readByteArray().joinToString()}/${partial.read()}")
    val short = ByteArrayInputStream(byteArrayOf(7, 8))
    println("stream-write-eof:${bufferFailure { buffer.write(short, 3L) }}/${buffer.readByteArray().joinToString()}")
    val untouched = ByteArrayInputStream(byteArrayOf(9))
    println("stream-write-negative:${bufferFailure { buffer.write(untouched, -1L) }}/${untouched.read()}/${buffer.size}")
    val target = Buffer()
    buffer.write(byteArrayOf(10, 11, 12))
    buffer.copyTo(target.asOutputStream(), startIndex = 1L)
    println("stream-copy-default-end:${target.readByteArray().joinToString()}/${buffer.size}")
    buffer.copyTo(target.asOutputStream(), endIndex = 1L)
    println("stream-copy-default-start:${target.readByteArray().joinToString()}/${buffer.size}")
    println("stream-copy-invalid:${bufferFailure { buffer.copyTo(target.asOutputStream(), -1L, 0L) }}/${bufferFailure { buffer.copyTo(target.asOutputStream(), 2L, 1L) }}/${target.size}/${buffer.size}")
    buffer.readTo(target.asOutputStream(), 1L)
    println("stream-read-count:${target.readByteArray().joinToString()}/${buffer.size}")
    buffer.readTo(target.asOutputStream())
    println("stream-read-default:${target.readByteArray().joinToString()}/${buffer.size}")
    println("stream-read-invalid:${bufferFailure { buffer.readTo(target.asOutputStream(), 1L) }}/${bufferFailure { buffer.readTo(target.asOutputStream(), -1L) }}/${target.size}")
    val closed = byteArrayOf(13).inputStream()
    closed.close()
    println("bytearray-close-noop:${closed.read()}/${closed.read()}")
    val latin: Charset = Charsets.ISO_8859_1
    println("charset-constructor:${String(byteArrayOf(0, -23, 0), 1, 1, latin)}/${String(byteArrayOf(-23), latin)}")
    println("charset-constructor-bounds:${bufferFailure { String(byteArrayOf(1), -1, 0, latin) }}/${bufferFailure { String(byteArrayOf(1), 0, 2, latin) }}")
    println("charset-input-stream:${"é".byteInputStream(latin).read()}")
    println("charset-reader:${byteArrayOf(-23).inputStream().bufferedReader(latin).readText()}")
    val charsets = listOf(Charsets.UTF_8, Charsets.ISO_8859_1, Charsets.US_ASCII, Charsets.UTF_16, Charsets.UTF_16BE, Charsets.UTF_16LE)
    for (charset in charsets) {
        val encoded = "Aé".encodeToByteString(charset)
        println("charset-roundtrip:${charset.name()}/${encoded.toByteArray().joinToString()}/${encoded.decodeToString(charset)}")
    }
    for (charset in listOf(Charsets.UTF_8, Charsets.ISO_8859_1, Charsets.US_ASCII, Charsets.UTF_16BE)) {
        val pair = "😀".encodeToByteString(charset)
        val unpaired = "\uD800".encodeToByteString(charset)
        println("charset-replacement:${charset.name()}/${pair.toByteArray().joinToString()}/${unpaired.toByteArray().joinToString()}")
    }
}
public fun runCharsetEmptyMalformedProbe() {
    for (charset in listOf(Charsets.UTF_8, Charsets.ISO_8859_1, Charsets.US_ASCII, Charsets.UTF_16, Charsets.UTF_16BE, Charsets.UTF_16LE)) {
        println("charset-empty:${charset.name()}/${"".encodeToByteString(charset).size}")
    }
    val inputs = listOf(byteArrayOf(-64, -81), byteArrayOf(-19, -96, -128), byteArrayOf(-30, -126), byteArrayOf(-30, 65))
    for (bytes in inputs) {
        println("charset-utf8-malformed:${bytes.toString(Charsets.UTF_8).map { it.code }.joinToString()}")
    }
    for (bytes in listOf(byteArrayOf(-40, 0, 0, 65), byteArrayOf(-40, 0, -36, 0, 0))) {
        println("charset-utf16-malformed:${bytes.toString(Charsets.UTF_16BE).map { it.code }.joinToString()}")
    }
}

private fun modelFailure(block: () -> Unit): String = try { block(); "none" } catch (e: Exception) {
    when (e) {
        is IllegalCharsetNameException -> "IllegalCharset:${e.charsetName}"
        is UnsupportedCharsetException -> "UnsupportedCharset:${e.charsetName}"
        is IndexOutOfBoundsException -> "Bounds"
        is IllegalArgumentException -> "Argument"
        is IOException -> "IO"
        else -> throw e
    }
}
private fun closeInteropErased(resource: AutoCloseable) { resource.close() }
public fun runNativeModelPrerequisitesProbe() {
    val channel = Buffer().asByteChannel()
    println("model-beans:${ByteBuffer.allocate(1).asReadOnlyBuffer().isReadOnly}/${ByteBuffer.allocateDirect(1).isDirect}/${channel.isOpen}")
    for (name in listOf("UTF8", "ASCII", "latin1", "utf-32", "UTF_32LE", "UnicodeBigUnmarked")) {
        println("model-for-name:$name/${Charset.forName(name).name()}")
    }
    println("model-illegal:${modelFailure { Charset.forName("<bad>") }}")
    println("model-unsupported:${modelFailure { Charset.forName("missing-1762") }}")
    println("model-output-capacity:${modelFailure { ByteArrayOutputStream(-1) }}")
    val out = ByteArrayOutputStream(0)
    out.write(byteArrayOf(1, 2, 3), 1, 2)
    val snapshot = out.toByteArray()
    snapshot[0] = 99
    println("model-output-snapshot:${out.toByteArray().joinToString()}/${out.size()}")
    out.close()
    out.write(255)
    println("model-output-close-noop:${out.toByteArray().joinToString()}")
    println("model-output-bounds:${modelFailure { out.write(byteArrayOf(4), -1, 1) }}/${out.size()}")
    out.reset()
    out.write("é".toByteArray(Charsets.ISO_8859_1))
    println("model-output-charsets:${out.toString(Charsets.ISO_8859_1)}/${out.toString("ISO-8859-1")}")
    println("model-output-invalid-charset:${modelFailure { out.toString("<bad>") }}/${modelFailure { out.toString("missing-1762") }}")
    out.reset()
    val buffer = Buffer().apply { write(byteArrayOf(5, 6, 7)) }
    buffer.copyTo(out, 1L)
    println("model-output-copy:${out.toByteArray().joinToString()}/${buffer.size}")
    buffer.readTo(out)
    println("model-output-drain:${out.toByteArray().joinToString()}/${buffer.size}")
    out.reset()
    val pending = Buffer().apply { write(byteArrayOf(8, 9, 10)) }
    out.asSink().write(pending, 2L)
    println("model-output-raw-sink:${out.toByteArray().joinToString()}/${pending.readByte()}")
    val erased: Any = out
    println("model-output-types:${erased is ByteArrayOutputStream}/${erased is OutputStream}/${erased is AutoCloseable}")
    var inputCloses = 0
    val input: InputStream = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
        override fun close() { inputCloses++ }
    }.buffered().asInputStream()
    closeInteropErased(input)
    println("model-input-erased-close:$inputCloses/${modelFailure { input.read() }}")
    var outputCloses = 0
    val output: OutputStream = object : RawSink {
        override fun write(source: Buffer, byteCount: Long) { source.skip(byteCount) }
        override fun flush() {}
        override fun close() { outputCloses++ }
    }.buffered().asOutputStream()
    closeInteropErased(output)
    println("model-output-erased-close:$outputCloses/${modelFailure { output.write(1) }}")
}

private fun storageFailure(block: () -> Unit): String = try { block(); "none" } catch (e: Exception) {
    when(e) { is java.io.IOException -> "IO"; is IndexOutOfBoundsException -> "Bounds"; else -> throw e }
}
public fun runStreamStorageProbe() {
    val bytes = byteArrayOf(1, 2, 3)
    val input = ByteArrayInputStream(bytes)
    bytes[0] = 9
    println("storage-constructor-alias:${input.read()}/${input.markSupported()}")
    input.mark(0)
    println("storage-mark-first:${input.read()}")
    input.reset()
    bytes[1] = 8
    println("storage-reset-alias:${input.read()}")
    input.close()
    println("storage-close-mark:${input.read()}/${input.available()}")
    input.reset()
    println("storage-reset-after-close:${input.read()}")
    val ranged = bytes.inputStream(1, 2)
    bytes[1] = 7
    println("storage-extension-range-alias:${ranged.read()}/${ranged.markSupported()}")
    ranged.reset()
    println("storage-extension-range-initial-mark:${ranged.read()}")
    val memory = ByteArrayOutputStream()
    val writer = memory.bufferedWriter(Charsets.ISO_8859_1)
    writer.write("é")
    println("storage-writer-before-flush:${memory.size()}")
    writer.flush()
    println("storage-writer-charset:${memory.toByteArray().joinToString()}")
    writer.close()
    println("storage-writer-closed:${storageFailure { writer.write("x") }}/${memory.toByteArray().joinToString()}")
    var writes = 0
    var flushes = 0
    var closes = 0
    val target = Buffer()
    val sink = object : RawSink {
        override fun write(source: Buffer, byteCount: Long) { writes++; target.write(source, byteCount) }
        override fun flush() { flushes++ }
        override fun close() { closes++ }
    }.buffered()
    val callbackWriter = sink.asOutputStream().bufferedWriter(Charsets.UTF_16BE)
    callbackWriter.write("é")
    callbackWriter.close()
    println("storage-callback-writer:${target.readByteArray().joinToString()}/$writes/$flushes/$closes")
}

public fun runStreamDescriptionProbe() {
    val buffer = Buffer()
    val input = buffer.asInputStream()
    val output = buffer.asOutputStream()
    println("stream-descriptions-empty:${input.toString() == "${buffer}.asInputStream()"}/${output.toString() == "${buffer}.asOutputStream()"}")
    buffer.writeByte(7)
    println("stream-descriptions-updated:${input.toString() == "${buffer}.asInputStream()"}/${output.toString() == "${buffer}.asOutputStream()"}")
    val failure = IOException("description")
    val brokenSource = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
        override fun close() {}
        override fun toString(): String = throw failure
    }.buffered().asInputStream()
    println("stream-description-source-error:${try { brokenSource.toString(); false } catch(e: IOException) { e === failure }}")
    val brokenSink = object : RawSink {
        override fun write(source: Buffer, byteCount: Long) { source.skip(byteCount) }
        override fun flush() {}
        override fun close() {}
        override fun toString(): String = throw failure
    }.buffered().asOutputStream()
    println("stream-description-sink-error:${try { brokenSink.toString(); false } catch(e: IOException) { e === failure }}")
}

public fun runSequenceCompositionProbe() {
    val first = Buffer().apply { write(byteArrayOf(1, 2)) }
    val second = Buffer().apply { writeByte(3) }
    val chain = SequenceInputStream(first.asInputStream(), second.asInputStream())
    println("sequence-construction-lazy:${first.size}/${second.size}")
    println("sequence-read-first:${chain.read()}/${chain.available()}")
    val data = ByteArray(3) { 9 }
    println("sequence-range-first-only:${chain.read(data, 1, 2)}/${data.joinToString()}/${second.size}")
    println("sequence-read-rest:${chain.readBytes().joinToString()}")
    val left = Buffer().apply { writeByte(4) }.asInputStream().asSource().buffered()
    val right = Buffer().apply { writeByte(5) }.asInputStream().asSource().buffered()
    val l = left.asInputStream(); val r = right.asInputStream()
    SequenceInputStream(l, r).close()
    println("sequence-close-both:${try { l.read(); false } catch(e: IOException) { true }}/${try { r.read(); false } catch(e: IOException) { true }}")
    val failure = IOException("read identity")
    val broken = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = throw failure
        override fun close() {}
    }.buffered().asInputStream()
    val error = SequenceInputStream(broken, Buffer().asInputStream())
    println("sequence-source-error:${try { error.read(); false } catch(e: IOException) { e === failure }}")
    error.close()
    val nested = SequenceInputStream(SequenceInputStream(Buffer().apply { writeByte(6) }.asInputStream(), Buffer().asInputStream()), Buffer().apply { writeByte(7) }.asInputStream())
    println("sequence-nested:${nested.readBytes().joinToString()}")
}

private fun sequenceEdgeFailure(action: () -> Unit): String = try { action(); "none" } catch(e: Exception) {
    when(e) { is IndexOutOfBoundsException -> "Bounds"; is IOException -> "IO"; else -> throw e }
}
public fun runSequenceEdgeProbe() {
    val empty = SequenceInputStream(Buffer().asInputStream(), Buffer().asInputStream())
    println("sequence-zero-empty:${empty.read(ByteArray(0), 0, 0)}")
    println("sequence-invalid-empty:${sequenceEdgeFailure { empty.read(ByteArray(0), -1, 0) }}")
    empty.close()
    println("sequence-invalid-closed:${empty.read(ByteArray(0), -1, 0)}")
    val source = Buffer().asInputStream().asSource().buffered()
    val sourceInput = source.asInputStream()
    source.close()
    val closed = SequenceInputStream(sourceInput, Buffer().asInputStream())
    println("sequence-closed-source-bounds:${sequenceEdgeFailure { closed.read(ByteArray(0), -1, 0) }}")
    var firstCloses = 0; var secondCloses = 0
    val failure = IOException("first close")
    val first = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
        override fun close() { firstCloses++; throw failure }
    }.buffered().asInputStream()
    val second = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
        override fun close() { secondCloses++ }
    }.buffered().asInputStream()
    val closeChain = SequenceInputStream(first, second)
    val same = try { closeChain.close(); false } catch(e: IOException) { e === failure }
    println("sequence-close-error:$same/$firstCloses/$secondCloses")
}

public fun runSequenceCopyProbe() {
    val first = Buffer().apply { write(byteArrayOf(1, 2)) }
    val second = Buffer().apply { writeByte(3) }
    val chain = SequenceInputStream(first.asInputStream(), second.asInputStream())
    println("sequence-mark-supported:${chain.markSupported()}")
    val destination = Buffer()
    val count = chain.copyTo(destination.asOutputStream(), bufferSize = 1)
    println("sequence-copy-all:$count/${destination.readByteArray().joinToString()}/${first.size}/${second.size}")
    val failure = IOException("copy identity")
    val broken = object : RawSource {
        override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = throw failure
        override fun close() {}
    }.buffered().asInputStream()
    val errorChain = SequenceInputStream(Buffer().apply { writeByte(7) }.asInputStream(), broken)
    val partial = Buffer()
    val same = try { errorChain.copyTo(partial.asOutputStream(), bufferSize = 1); false } catch(e: IOException) { e === failure }
    println("sequence-copy-error:$same/${partial.readByteArray().joinToString()}")
}
