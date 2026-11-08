package java.io

public class CharArrayWriter : Writer {
    private val buffer = StringBuilder()
    private var closed: Boolean = false

    public constructor()

    public constructor(initialSize: Int)

    public fun write(value: Int): Unit {
        checkOpen()
        buffer.append(value.toChar())
    }

    public fun write(value: CharArray): Unit = write(value, 0, value.size)

    public fun write(value: CharArray, offset: Int, length: Int): Unit {
        checkOpen()
        if (offset < 0 || length < 0 || offset > value.size - length) {
            throw IndexOutOfBoundsException()
        }
        var i = 0
        while (i < length) {
            buffer.append(value[offset + i])
            i += 1
        }
    }

    public override fun write(value: String): Unit {
        checkOpen()
        buffer.append(value)
    }

    public fun write(value: String, offset: Int, length: Int): Unit {
        checkOpen()
        if (offset < 0 || length < 0 || offset > value.length - length) {
            throw IndexOutOfBoundsException()
        }
        buffer.append(value, offset, offset + length)
    }

    public fun append(value: Char): CharArrayWriter {
        checkOpen()
        buffer.append(value)
        return this
    }

    public fun append(value: CharSequence?): CharArrayWriter {
        checkOpen()
        buffer.append(value?.toString() ?: "null")
        return this
    }

    public fun append(value: CharSequence?, startIndex: Int, endIndex: Int): CharArrayWriter {
        checkOpen()
        val text = value?.toString() ?: "null"
        if (startIndex < 0 || endIndex < startIndex || endIndex > text.length) {
            throw IndexOutOfBoundsException()
        }
        buffer.append(text, startIndex, endIndex)
        return this
    }

    public fun toCharArray(): CharArray = buffer.toString().toCharArray()

    public fun toString(): String = buffer.toString()

    public fun size(): Int = buffer.length

    public fun reset(): Unit {
        checkOpen()
        buffer.setLength(0)
    }

    public override fun flush(): Unit {
        checkOpen()
    }

    public override fun close(): Unit {
        closed = true
    }

    private fun checkOpen(): Unit {
        if (closed) throw IOException()
    }
}
