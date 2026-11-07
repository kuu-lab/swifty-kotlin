package java.io

public class LineNumberReader(private val `in`: Reader) : Reader() {
    private var lineNumber: Int = 0
    private var marked: Boolean = false
    private var markLine: Int = 0
    private val markBuffer = ArrayList<Char>()
    private val pushback = ArrayList<Char>()
    private var lastWasCR: Boolean = false
    private var pendingChars: Int = 0
    private var closed: Boolean = false

    public constructor(`in`: Reader, size: Int) : this(`in`)

    public fun read(): Int {
        checkOpen()
        val c = nextChar()
        if (c < 0) return -1
        trackLine(c.toChar())
        return c
    }

    public override fun read(buffer: CharArray, offset: Int, length: Int): Int {
        checkOpen()
        if (offset < 0 || length < 0 || offset > buffer.size - length) {
            throw IndexOutOfBoundsException()
        }
        if (length == 0) return 0
        var copied = 0
        while (copied < length) {
            val c = nextChar()
            if (c < 0) break
            trackLine(c.toChar())
            buffer[offset + copied] = c.toChar()
            copied += 1
        }
        return if (copied == 0) -1 else copied
    }

    public fun readLine(): String? {
        checkOpen()
        val sb = StringBuilder()
        while (true) {
            val c = nextChar()
            if (c < 0) {
                return if (sb.isEmpty()) null else sb.toString()
            }
            if (c == '\n'.code) {
                trackLine('\n')
                return sb.toString()
            }
            if (c == '\r'.code) {
                trackLine('\r')
                val ahead = nextChar()
                if (ahead == '\n'.code) {
                    trackLine('\n')
                } else if (ahead >= 0) {
                    pushback.add(0, ahead.toChar())
                }
                return sb.toString()
            }
            trackLine(c.toChar())
            sb.append(c.toChar())
        }
    }

    public fun skip(count: Long): Long {
        checkOpen()
        if (count < 0L) throw IllegalArgumentException()
        var remaining = count
        var skipped = 0L
        val buffer = CharArray(8192)
        while (remaining > 0L) {
            val chunk = minOf(remaining, buffer.size.toLong()).toInt()
            val n = read(buffer, 0, chunk)
            if (n <= 0) break
            skipped += n
            remaining -= n
        }
        return skipped
    }

    public fun ready(): Boolean = false

    public fun mark(readAheadLimit: Int): Unit {
        checkOpen()
        marked = true
        markLine = lineNumber
        markBuffer.clear()
    }

    public fun reset(): Unit {
        checkOpen()
        if (!marked) throw IOException("Stream not marked")
        pushback.clear()
        var i = markBuffer.size - 1
        while (i >= 0) {
            pushback.add(0, markBuffer[i])
            i -= 1
        }
        lineNumber = markLine
        lastWasCR = false
    }

    public fun markSupported(): Boolean = true

    public fun getLineNumber(): Int = lineNumber

    public fun setLineNumber(lineNo: Int): Unit {
        checkOpen()
        lineNumber = lineNo
    }

    public override fun close(): Unit {
        closed = true
        `in`.close()
    }

    private fun nextChar(): Int {
        if (pushback.isNotEmpty()) {
            return pushback.removeAt(0).code
        }
        val buffer = CharArray(1)
        val n = `in`.read(buffer, 0, 1)
        if (n <= 0) {
            if (pendingChars > 0) {
                lineNumber += 1
                pendingChars = 0
            }
            return -1
        }
        val c = buffer[0]
        if (marked) markBuffer.add(c)
        return c.code
    }

    private fun trackLine(c: Char) {
        when (c) {
            '\r' -> {
                lineNumber += 1
                lastWasCR = true
                pendingChars = 0
            }
            '\n' -> {
                if (!lastWasCR) lineNumber += 1
                lastWasCR = false
                pendingChars = 0
            }
            else -> {
                lastWasCR = false
                pendingChars += 1
            }
        }
    }

    private fun checkOpen(): Unit {
        if (closed) throw IOException()
    }
}
