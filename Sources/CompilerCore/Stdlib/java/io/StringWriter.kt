package java.io

import java.lang.StringBuffer
import kotlin.text.StringBuilder

public class StringWriter : Writer {
    private var buffer: StringBuilder = StringBuilder()

    public constructor()

    public constructor(initialSize: Int) {
        if (initialSize < 0) throw IllegalArgumentException()
        buffer = StringBuilder(initialSize)
    }

    public fun write(value: Int): Unit {
        buffer.append(value.toChar())
    }

    public fun write(value: CharArray): Unit {
        write(value, 0, value.size)
    }

    public fun write(value: CharArray, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.size - length) {
            throw IndexOutOfBoundsException()
        }
        var index = 0
        while (index < length) {
            buffer.append(value[offset + index])
            index += 1
        }
    }

    public fun write(value: String): Unit {
        buffer.append(value)
    }

    public fun write(value: String, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.length - length) {
            throw IndexOutOfBoundsException()
        }
        buffer.append(value.substring(offset, offset + length))
    }

    public fun append(value: Char): StringWriter {
        buffer.append(value)
        return this
    }

    public fun append(value: CharSequence?): StringWriter {
        buffer.append(value?.toString() ?: "null")
        return this
    }

    public fun append(value: CharSequence?, startIndex: Int, endIndex: Int): StringWriter {
        val text = value?.toString() ?: "null"
        if (startIndex < 0 || endIndex < startIndex || endIndex > text.length) {
            throw IndexOutOfBoundsException()
        }
        buffer.append(text.substring(startIndex, endIndex))
        return this
    }

    public fun getBuffer(): StringBuffer = buffer

    public fun flush(): Unit {}

    public override fun close(): Unit {}

    public override fun toString(): String = buffer.toString()
}
