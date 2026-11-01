package java.util

import java.io.File
import java.io.InputStream
import java.nio.charset.Charset
import java.nio.file.Path

/** Scanner over a string input. Delimiters are Kotlin regular expressions. */
public class Scanner(private val source: String) : AutoCloseable {
    /**
     * Scanner over the file's contents (JVM `Scanner(File)`). The native
     * default charset is UTF-8 (docs/stdlib-pipeline.md), so the no-charset
     * overloads decode with `Charsets.UTF_8`.
     */
    public constructor(file: File) : this(scannerReadFile(file, null))

    public constructor(file: File, charsetName: String) : this(
        scannerReadFile(file, Charset.forName(charsetName))
    )

    public constructor(file: File, charset: Charset) : this(scannerReadFile(file, charset))

    /**
     * Scanner over the stream's remaining bytes (JVM `Scanner(InputStream)`).
     * The bundled runtime drains the stream eagerly at construction; JVM's
     * lazy pull produces the same token sequence for batch/piped input.
     */
    public constructor(input: InputStream) : this(scannerReadStream(input, null))

    public constructor(input: InputStream, charsetName: String) : this(
        scannerReadStream(input, Charset.forName(charsetName))
    )

    public constructor(input: InputStream, charset: Charset) : this(
        scannerReadStream(input, charset)
    )

    /** Scanner over the file at `path` (JVM `Scanner(Path)`). */
    public constructor(path: Path) : this(scannerReadFile(path.toFile(), null))

    public constructor(path: Path, charsetName: String) : this(
        scannerReadFile(path.toFile(), Charset.forName(charsetName))
    )

    public constructor(path: Path, charset: Charset) : this(
        scannerReadFile(path.toFile(), charset)
    )

    private var delimiter: Regex = Regex("\\s+")
    private var position = 0
    private var radix = 10
    private var closed = false

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
        skipDelimiters()
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
        return position < source.length
    }

    public fun nextLine(): String {
        ensureOpen()
        if (position >= source.length) throw NoSuchElementException()
        var end = position
        while (end < source.length && source[end] != '\n' && source[end] != '\r') end++
        val line = source.substring(position, end)
        if (end < source.length && source[end] == '\r') end++
        if (end < source.length && source[end] == '\n') end++
        position = end
        return line
    }

    override fun close() {
        closed = true
    }

    private fun peekToken(): String? {
        ensureOpen()
        skipDelimiters()
        if (position >= source.length) return null
        val match = delimiter.find(source, position)
        val end = if (match == null) source.length else match.range.first
        return source.substring(position, end)
    }

    private fun skipDelimiters() {
        while (position < source.length) {
            val match = delimiter.find(source, position) ?: return
            if (match.range.first != position) return
            val end = match.range.last + 1
            if (end <= position) return
            position = end
        }
    }

    private fun ensureOpen() {
        if (closed) throw IllegalStateException("Scanner is closed")
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
