@file:OptIn(kotlinx.io.InternalIoApi::class, kotlinx.io.DelicateIoApi::class)
import kotlinx.io.*

fun codeUnits(value: String?): String {
    if (value == null) return "null"
    val result = StringBuilder()
    var index = 0
    while (index < value.length) {
        if (index > 0) result.append(',')
        result.append(value[index].code)
        index += 1
    }
    return result.toString()
}

fun unread(buffer: Buffer): String = buffer.copy().readByteArray().toHexString()

fun point(label: String, bytes: ByteArray, buffered: Boolean = false) {
    val storage = Buffer()
    storage.write(bytes)
    val source: Source = if (buffered) (storage as RawSource).buffered() else storage
    try { println(label + ":point=" + source.readCodePointValue() + ":left=" + unread(source.buffer)) }
    catch (e: EOFException) { println(label + ":EOF:" + e.message + ":left=" + unread(source.buffer)) }
}

fun decode(label: String, bytes: ByteArray) {
    val buffer = Buffer()
    buffer.write(bytes)
    println(label + ":units=" + codeUnits(buffer.readString()) + ":left=" + buffer.size)
}

class ObservedChars(private val text: String) : CharSequence {
    var accesses: String = ""
    override val length: Int get() = text.length
    override fun get(index: Int): Char {
        accesses += index.toString()
        return text[index]
    }
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = text.substring(startIndex, endIndex)
    override fun toString(): String = "wrong-toString"
}

class ThrowingChars : CharSequence {
    override val length: Int get() = 2
    override fun get(index: Int): Char = if (index == 0) 'é' else throw IllegalArgumentException("charAt(1)")
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = this
}

fun strict(label: String, text: String, limit: Long) {
    val buffer = Buffer()
    buffer.writeString(text)
    try { println(label + ":line=" + codeUnits(buffer.readLineStrict(limit)) + ":left=" + unread(buffer)) }
    catch (e: EOFException) { println(label + ":EOF:" + e.message + ":left=" + unread(buffer)) }
    catch (e: IllegalArgumentException) { println(label + ":IAE:" + e.message + ":left=" + unread(buffer)) }
}

fun main() {
    point("empty", byteArrayOf())
    point("truncated2", byteArrayOf(0xdf.toByte()))
    point("truncated3", byteArrayOf(0xe2.toByte(), 0x82.toByte()))
    point("truncated4", byteArrayOf(0xf0.toByte(), 0x9f.toByte(), 0x98.toByte()))
    point("sourceTruncated", byteArrayOf(0xe2.toByte(), 0x82.toByte()), true)
    point("nonContinuation", byteArrayOf(0xe2.toByte(), 0x82.toByte(), 65))
    point("continuation", byteArrayOf(0x80.toByte(), 65))
    point("unknown", byteArrayOf(0xff.toByte(), 65))
    point("overlong2", byteArrayOf(0xc0.toByte(), 0x80.toByte(), 65))
    point("overlong3", byteArrayOf(0xe0.toByte(), 0x80.toByte(), 0x80.toByte(), 65))
    point("overlong4", byteArrayOf(0xf0.toByte(), 0x80.toByte(), 0x80.toByte(), 0x80.toByte(), 65))
    point("surrogate", byteArrayOf(0xed.toByte(), 0xa0.toByte(), 0x80.toByte(), 65))
    point("outOfRange", byteArrayOf(0xf4.toByte(), 0x90.toByte(), 0x80.toByte(), 0x80.toByte(), 65))
    point("valid4", byteArrayOf(0xf4.toByte(), 0x8f.toByte(), 0xbf.toByte(), 0xbf.toByte(), 65))
    decode("stringTruncated", byteArrayOf(0xf0.toByte(), 0x9f.toByte(), 0x98.toByte()))
    decode("stringBadContinuation", byteArrayOf(0xf0.toByte(), 0x9f.toByte(), 65, 0x80.toByte()))
    decode("stringOutOfRange", byteArrayOf(0xf4.toByte(), 0x90.toByte(), 0x80.toByte(), 0x80.toByte()))
    val observed = ObservedChars("AB")
    val written = Buffer()
    written.writeString(observed)
    println("chars:" + observed.accesses + ":" + unread(written))
    val broken = Buffer()
    try { broken.writeString(ThrowingChars()) }
    catch (e: IllegalArgumentException) { println("charThrow:" + e.message + ":left=" + unread(broken)) }
    val partial = Buffer()
    partial.writeString("\ud800A\udc00\ud83d\ude00", 0, 5)
    println("utf16:" + unread(partial))
    val range = Buffer()
    range.writeString("X\ud83d\ude00Y", 1, 2)
    println("splitPair:" + unread(range))
    try { range.writeString("abc", -1, 2) }
    catch (e: IndexOutOfBoundsException) { println("rangeIOOB:" + e.message + ":left=" + unread(range)) }
    try { range.writeString("abc", 2, 1) }
    catch (e: IllegalArgumentException) { println("rangeIAE:" + e.message + ":left=" + unread(range)) }
    val points = Buffer()
    points.writeCodePointValue(0xd800)
    points.writeCodePointValue(0xdfff)
    points.writeCodePointValue(0x10000)
    println("writtenPoints:" + unread(points))
    try { points.writeCodePointValue(-1) }
    catch (e: IllegalArgumentException) { println("negativePoint:" + e.message + ":left=" + unread(points)) }
    try { points.writeCodePointValue(0x110000) }
    catch (e: IllegalArgumentException) { println("largePoint:" + e.message + ":left=" + unread(points)) }
    val closed = discardingSink().buffered()
    closed.close()
    try { closed.writeString("X") }
    catch (e: IllegalStateException) { println("closedString:" + e.message + ":left=" + unread(closed.buffer)) }
    val lines = Buffer()
    lines.writeString("\nA\r\nB\rC")
    println("lines:" + codeUnits(lines.readLine()) + ":" + codeUnits(lines.readLine()) + ":" + codeUnits(lines.readLine()) + ":" + codeUnits(lines.readLine()))
    strict("limitLF0", "\nZ", 0)
    strict("limitCRLF0", "\r\nZ", 0)
    strict("limitUTF8before", "α\nZ", 1)
    strict("limitUTF8at", "α\nZ", 2)
    strict("limitCRbefore", "ab\r\nZ", 1)
    strict("limitCRat", "ab\r\nZ", 2)
    strict("bareCR", "ab\r", 2)
    strict("noLF", "ab", Long.MAX_VALUE)
    strict("negativeLimit", "\nZ", -1)
    val segment = Buffer()
    segment.write(ByteArray(8191) { 65 })
    segment.writeString("😀\r\nZ")
    segment.skip(8191)
    println("segmentPoint:" + segment.readCodePointValue() + ":left=" + unread(segment))
    println("segmentLine:" + codeUnits(segment.readLineStrict(0)) + ":left=" + unread(segment))
    val crBoundary = Buffer()
    crBoundary.write(ByteArray(8191) { 65 })
    crBoundary.writeString("\r\nZ")
    println("segmentCRLF:" + crBoundary.readLineStrict(8191).length + ":left=" + unread(crBoundary))
}
