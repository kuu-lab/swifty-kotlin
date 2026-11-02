package java.util

import java.io.File
import java.nio.charset.Charset
import java.nio.file.Path

/** Scanner over a string or character input. Delimiters are Kotlin regular
 * expressions. Stream-backed scanners read lazily like the JDK — they only
 * consume input as `next*`/`hasNext*` calls require, and never block waiting
 * for data they do not need yet. */
public class Scanner : AutoCloseable {
    private var source: String
    private var stream: java.io.InputStream? = null
    private var charset: java.nio.charset.Charset? = null
    private var streamEof = false
    private val pendingBytes = mutableListOf<Byte>()

    private var delimiter: Regex = Regex("\\s+")
    private var position = 0
    private var radix = 10
    private var closed = false

    public constructor(source: String) {
        this.source = source
    }

    /** Scanner reading text from `source` (UTF-8). Reads are lazy: the stream
     * is consumed only as needed, so scanning stops without waiting for EOF. */
    public constructor(source: java.io.InputStream) {
        this.source = ""
        this.stream = source
    }

    /** Scanner reading text from `source` decoded with the named charset. */
    public constructor(source: java.io.InputStream, charsetName: String) {
        this.source = ""
        this.stream = source
        this.charset = java.nio.charset.Charset.forName(charsetName)
    }

    /** Scanner reading all remaining text from `source`. */
    public constructor(source: java.io.Reader) {
        this.source = source.readText()
    }

    public constructor(file: File) : this(scannerReadFile(file, null))

    public constructor(file: File, charsetName: String) : this(
        scannerReadFile(file, Charset.forName(charsetName))
    )

    public constructor(file: File, charset: Charset) : this(scannerReadFile(file, charset))

    public constructor(path: Path) : this(scannerReadFile(path.toFile(), null))

    public constructor(path: Path, charsetName: String) : this(
        scannerReadFile(path.toFile(), Charset.forName(charsetName))
    )

    public constructor(path: Path, charset: Charset) : this(
        scannerReadFile(path.toFile(), charset)
    )

    public fun useDelimiter(pattern: String): Scanner {
        ensureOpen()
        delimiter = Regex(pattern)
        return this
    }

    public fun useRadix(radix: Int): Scanner {
        ensureOpen()
        if (radix < 2 || radix > 36) throw IllegalArgumentException("radix out of range")
        this.radix = radix
        return this
    }

    public fun radix(): Int = radix

    public fun hasNext(): Boolean {
        ensureOpen()
        fill()
        skipDelimiters()
        fill()
        return position < source.length
    }

    public fun hasNext(pattern: String): Boolean {
        val token = peekToken() ?: return false
        return Regex(pattern).matches(token)
    }

    public fun next(): String {
        val token = peekToken() ?: throw NoSuchElementException()
        position += token.length
        return token
    }

    public fun next(pattern: String): String {
        val token = peekToken() ?: throw NoSuchElementException()
        if (!Regex(pattern).matches(token)) throw NoSuchElementException()
        position += token.length
        return token
    }

    public fun hasNextInt(): Boolean = hasNextInt(radix)

    public fun hasNextInt(radix: Int): Boolean = peekToken()?.toIntOrNull(radix) != null

    public fun nextInt(): Int = nextInt(radix)

    public fun nextInt(radix: Int): Int = next().toInt(radix)

    public fun hasNextLong(): Boolean = hasNextLong(radix)

    public fun hasNextLong(radix: Int): Boolean = peekToken()?.toLongOrNull(radix) != null

    public fun nextLong(): Long = nextLong(radix)

    public fun nextLong(radix: Int): Long = next().toLong(radix)

    public fun hasNextDouble(): Boolean = peekToken()?.toDoubleOrNull() != null

    public fun nextDouble(): Double = next().toDouble()

    public fun hasNextLine(): Boolean {
        ensureOpen()
        while (position >= source.length && pump()) {
        }
        return position < source.length
    }

    public fun nextLine(): String {
        ensureOpen()
        while (position >= source.length && pump()) {
        }
        if (position >= source.length) throw NoSuchElementException()
        var end = position
        while (true) {
            while (end < source.length && source[end] != '\n' && source[end] != '\r') end++
            if (end < source.length || streamEof || !pump()) break
        }
        val line = source.substring(position, end)
        if (end < source.length && source[end] == '\r') end++
        if (end < source.length && source[end] == '\n') end++
        position = end
        return line
    }

    override fun close() {
        closed = true
        stream?.close()
    }

    /** Pulls buffered stream data into [source], returning `true` when more
     * input may still arrive. */
    private fun fill() {
        while (position >= source.length && pump()) {
        }
    }

    private fun peekToken(): String? {
        ensureOpen()
        skipDelimiters()
        fill()
        if (position >= source.length) return null
        var match = delimiter.find(source, position)
        while (match == null && !streamEof) {
            if (!pump()) break
            match = delimiter.find(source, position)
        }
        val end = if (match == null) source.length else match.range.first
        return source.substring(position, end)
    }

    private fun skipDelimiters() {
        while (true) {
            while (position < source.length) {
                val match = delimiter.find(source, position) ?: return
                if (match.range.first != position) return
                val end = match.range.last + 1
                if (end <= position) return
                position = end
            }
            if (streamEof || !pump()) return
        }
    }

    private fun ensureOpen() {
        if (closed) throw IllegalStateException("Scanner is closed")
    }

    // -- lazy stream input -------------------------------------------------

    private fun pump(): Boolean {
        val s = stream ?: return false
        if (streamEof) return false
        val buf = ByteArray(1024)
        val n = s.read(buf)
        if (n <= 0) {
            streamEof = true
            decodeAvailable(final = true)
            return source.isNotEmpty()
        }
        for (i in 0 until n) pendingBytes.add(buf[i])
        decodeAvailable(final = false)
        return true
    }

    /** Decodes the maximal complete UTF-8 prefix of [pendingBytes] into
     * [source]. A trailing incomplete multi-byte sequence is kept pending so
     * a split character is never corrupted. */
    private fun decodeAvailable(final: Boolean) {
        var complete = pendingBytes.size
        if (!final && complete > 0) {
            var i = pendingBytes.size - 1
            while (i >= 0 && (pendingBytes[i].toInt() and 0xC0) == 0x80) i--
            if (i >= 0) {
                val lead = pendingBytes[i].toInt() and 0xFF
                val seqLen = when {
                    lead < 0x80 -> 1
                    lead and 0xE0 == 0xC0 -> 2
                    lead and 0xF0 == 0xE0 -> 3
                    else -> 4
                }
                if (pendingBytes.size - i < seqLen) complete = i
            }
        }
        if (complete > 0) {
            val bytes = ByteArray(complete) { pendingBytes[it] }
            val enc = charset
            source += if (enc == null) String(bytes) else String(bytes, enc)
            for (k in 0 until complete) pendingBytes.removeAt(0)
        }
    }
}

// KUU-4007: JVM `Scanner(File)` / `Scanner(Path)` throw FileNotFoundException
// when the target is missing, while `File.readText()` reports the same
// condition as kotlin.io.FileSystemException. Surface the JVM spelling here,
// matching the bundled convention that open failures map to
// FileNotFoundException (see `__kk_io_fs_open_read`).
private fun scannerReadFile(file: File, charset: Charset?): String {
    if (!file.exists()) throw java.io.FileNotFoundException(file.path)
    return if (charset == null) file.readText() else file.readText(charset)
}

private fun scannerReadStream(input: InputStream, charset: Charset?): String {
    val bytes = input.readBytes()
    return if (charset == null) bytes.decodeToString() else bytes.decodeToString(charset)
}
