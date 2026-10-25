package java.util

/** Scanner over a string input. Delimiters are Kotlin regular expressions. */
public class Scanner(private val source: String) : AutoCloseable {
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
