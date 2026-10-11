@file:OptIn(kotlinx.io.InternalIoApi::class)
package kuu1730contracts

import kotlinx.io.*

public class ChunkSource(public val data: Buffer, public val chunk: Long = 1L) : RawSource {
    public var reads: Int = 0
    public var closes: Int = 0
    public var readFailure: Throwable? = null
    public var closeFailure: Throwable? = null
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        reads++
        val failure = readFailure
        if (failure != null) throw failure
        return data.readAtMostTo(sink, minOf(byteCount, chunk))
    }
    override fun close() {
        closes++
        val failure = closeFailure
        if (failure != null) throw failure
    }
}

public class RecordingSink : RawSink {
    public val data: Buffer = Buffer()
    public var events: String = ""
    public var writeFailure: Throwable? = null
    public var closeFailure: Throwable? = null
    public var partialBeforeThrow: Boolean = false
    override fun write(source: Buffer, byteCount: Long) {
        events += "write($byteCount);"
        val failure = writeFailure
        if (failure != null) {
            if (partialBeforeThrow && byteCount > 0L) data.write(source, 1L)
            throw failure
        }
        data.write(source, byteCount)
    }
    override fun flush() { events += "flush;" }
    override fun close() {
        events += "close;"
        val failure = closeFailure
        if (failure != null) throw failure
    }
}

private fun bytes(text: String): Buffer {
    val result = Buffer()
    result.writeString(text)
    return result
}

private fun failureLabel(block: () -> Unit): String {
    try { block(); return "NONE" }
    catch (failure: EOFException) { return "EOF:" + failure.message }
    catch (failure: IllegalStateException) { return "STATE:" + failure.message }
    catch (failure: IllegalArgumentException) { return "ARG:" + failure.message }
    catch (failure: Throwable) { return "OTHER:" + failure.message }
}

public fun runContract() {
    val raw = ChunkSource(bytes("abc"))
    val source: Source = raw.buffered()
    println("request3=" + source.request(3L))
    println("short-reads=" + raw.reads + ":" + source.buffer.size)
    val output = ByteArray(5) { 95.toByte() }
    println("array-default-end=" + source.readAtMostTo(output, 1))
    println("array-content=" + output.joinToString(","))
    println("eof=" + source.readAtMostTo(Buffer(), 1L))
    println("request-zero=" + source.request(0L))
    println("negative=" + failureLabel { source.request(-1L) })

    val zeroRaw = ChunkSource(bytes("z"))
    val zero = zeroRaw.buffered()
    println("zero-buffer-data=" + zero.readAtMostTo(Buffer(), 0L))
    println("zero-buffer-fetch=" + zeroRaw.reads + ":" + zero.buffer.size)
    println("zero-array-data=" + zero.readAtMostTo(ByteArray(0)))
    println("zero-buffer-empty=" + ChunkSource(Buffer()).buffered().readAtMostTo(Buffer(), 0L))
    println("zero-array-empty=" + ChunkSource(Buffer()).buffered().readAtMostTo(ByteArray(0)))

    val short = ChunkSource(bytes("ab")).buffered()
    val partial = RecordingSink()
    println("readTo-eof=" + failureLabel { short.readTo(partial, 3L) })
    println("readTo-consumed=" + partial.data.readString() + ":" + short.buffer.size)
    val skipped = ChunkSource(bytes("a")).buffered()
    println("skip-eof=" + failureLabel { skipped.skip(2L) })

    val readRoot = IOException("read-root")
    val failingRaw = ChunkSource(bytes("keep"))
    failingRaw.readFailure = readRoot
    val failing = failingRaw.buffered()
    var readIdentity = false
    try { failing.readByte() } catch (failure: Throwable) { readIdentity = failure === readRoot }
    println("read-root-identity=" + readIdentity + ":" + failingRaw.data.size)

    val closingRaw = ChunkSource(bytes("ab"), 2L)
    val closing = closingRaw.buffered()
    closing.request(1L)
    closing.close()
    closing.close()
    println("source-close=" + closingRaw.closes + ":" + closing.buffer.size)
    println("source-closed=" + failureLabel { closing.readByte() })
    val closeRoot = IOException("close-root")
    val closeRaw = ChunkSource(bytes("abc"), 3L)
    closeRaw.closeFailure = closeRoot
    val closeSource = closeRaw.buffered()
    closeSource.request(1L)
    var closeIdentity = false
    try { closeSource.close() } catch (failure: Throwable) { closeIdentity = failure === closeRoot }
    closeSource.close()
    println("source-close-failure=" + closeIdentity + ":" + closeRaw.closes + ":" + closeSource.buffer.size)

    val target = RecordingSink()
    val sink: Sink = target.buffered()
    sink.write(ByteArray(8193) { 65.toByte() })
    println("hint=" + target.events + ":" + sink.buffer.size)
    sink.emit()
    println("emit=" + target.events + ":" + sink.buffer.size)
    sink.flush()
    sink.close()
    sink.close()
    println("flush-close=" + target.events + ":" + target.data.size)
    println("sink-closed=" + failureLabel { sink.flush() })

    val writeRoot = IOException("write-root")
    val sinkCloseRoot = IOException("sink-close-root")
    val dualRaw = RecordingSink()
    dualRaw.writeFailure = writeRoot
    dualRaw.closeFailure = sinkCloseRoot
    val dual = dualRaw.buffered()
    dual.writeByte(65.toByte())
    var dualIdentity = false
    try { dual.close() } catch (failure: Throwable) { dualIdentity = failure === writeRoot }
    dual.close()
    println("dual-close=" + dualIdentity + ":" + dualRaw.events + ":" + dual.buffer.size)
    val partialRaw = RecordingSink()
    partialRaw.writeFailure = writeRoot
    partialRaw.partialBeforeThrow = true
    val partialSink = partialRaw.buffered()
    partialSink.writeString("abc")
    var partialIdentity = false
    try { partialSink.emit() } catch (failure: Throwable) { partialIdentity = failure === writeRoot }
    println("partial-write=" + partialIdentity + ":" + partialRaw.data.readString() + ":" + partialSink.buffer.readString())

    val transferRaw = ChunkSource(bytes("abcdef"), 2L)
    val transferTarget = RecordingSink()
    val transferSink = transferTarget.buffered()
    println("transferFrom=" + transferSink.transferFrom(transferRaw))
    println("transfer-buffered=" + transferSink.buffer.readString() + ":" + transferTarget.events)
    val writeSource = ChunkSource(bytes("ab"))
    val writeTarget = RecordingSink()
    val writeSink = writeTarget.buffered()
    println("write-eof=" + failureLabel { writeSink.write(writeSource, 3L) })
    println("write-partial=" + writeSink.buffer.readString())
    val noOpRaw = ChunkSource(bytes("x"))
    writeSink.write(noOpRaw, 0L)
    println("write-zero=" + noOpRaw.reads)

    val defaultsRaw = RecordingSink()
    val defaults: Sink = defaultsRaw.buffered()
    defaults.write(byteArrayOf(65, 66, 67))
    defaults.write(byteArrayOf(68, 69, 70), 1)
    defaults.write(byteArrayOf(71, 72, 73), endIndex = 2)
    defaults.emit()
    println("sink-defaults=" + defaultsRaw.data.readString())
    val discard = discardingSink()
    val discarded = bytes("abc")
    discard.write(discarded, 2L)
    discard.flush()
    discard.close()
    discard.close()
    println("discard=" + discarded.readString())
    println("discard-range=" + failureLabel { discard.write(Buffer(), -1L) })

    val peekBase = Buffer()
    val emptyPeek = peekBase.peek()
    println("peek-empty=" + emptyPeek.request(1L))
    peekBase.writeString("abc")
    println("peek-after-append=" + emptyPeek.readString(3L) + ":" + peekBase.size)
    val first = peekBase.peek()
    val second = peekBase.peek()
    println("peek-multiple=" + first.readString(2L) + ":" + second.readString(3L) + ":" + peekBase.size)
    peekBase.readByte()
    first.skip(first.buffer.size)
    println("peek-consumed=" + failureLabel { first.readByte() })

    val large = bytes("a".repeat(8192) + "b".repeat(8192) + "end")
    val shared = large.copy()
    val largePeek = large.peek()
    largePeek.skip(16384L)
    println("peek-shared=" + largePeek.readString() + ":" + large.size + ":" + shared.size)
    val headPeek = large.peek()
    headPeek.readByte()
    large.skip(8192L)
    headPeek.skip(headPeek.buffer.size)
    println("peek-head-replaced=" + failureLabel { headPeek.readByte() })
    val ownerRaw = ChunkSource(bytes("ok"))
    val owner = ownerRaw.buffered()
    owner.peek().close()
    println("peek-close-owner=" + ownerRaw.closes + ":" + owner.readString())
    println("done")
}
