package java.util

public class StringTokenizer(
    private val source: String,
    private var delimiters: String = " \t\n\r\u000c",
    private val returnDelimiters: Boolean = false,
) : Enumeration<String> {
    private var position: Int = 0

    public fun hasMoreTokens(): Boolean = nextTokenBounds(position, delimiters) != null

    public fun nextToken(): String {
        val bounds = nextTokenBounds(position, delimiters) ?: throw NoSuchElementException()
        position = bounds.last + 1
        return source.substring(bounds.first, bounds.last + 1)
    }

    public fun nextToken(delimiters: String): String {
        this.delimiters = delimiters
        return nextToken()
    }

    public fun countTokens(): Int {
        var cursor = position
        var count = 0
        while (true) {
            val bounds = nextTokenBounds(cursor, delimiters) ?: return count
            count++
            cursor = bounds.last + 1
        }
    }

    override fun hasMoreElements(): Boolean = hasMoreTokens()

    override fun nextElement(): String = nextToken()

    private fun nextTokenBounds(start: Int, delimiters: String): IntRange? {
        var tokenStart = start
        val sourceLength = source.length

        if (returnDelimiters) {
            if (tokenStart >= sourceLength) return null
            if (isDelimiter(source[tokenStart], delimiters)) return tokenStart..tokenStart
        } else {
            while (tokenStart < sourceLength && isDelimiter(source[tokenStart], delimiters)) {
                tokenStart++
            }
            if (tokenStart >= sourceLength) return null
        }

        var tokenEnd = tokenStart
        while (tokenEnd < sourceLength && !isDelimiter(source[tokenEnd], delimiters)) {
            tokenEnd++
        }
        return tokenStart..(tokenEnd - 1)
    }

    private fun isDelimiter(character: Char, delimiters: String): Boolean {
        var index = 0
        while (index < delimiters.length) {
            if (character == delimiters[index]) return true
            index++
        }
        return false
    }
}
