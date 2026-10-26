package java.io

import java.lang.StringBuffer
import kotlin.internal.KsSymbolName

public class StringWriter : Writer {
    @KsSymbolName("__kk_string_writer_new_default")
    public constructor()

    @KsSymbolName("__kk_string_writer_new")
    public constructor(initialSize: Int)

    @KsSymbolName("__kk_buffered_writer_write")
    public external override fun write(value: String): Unit

    public fun write(value: Int): Unit = write(value.toChar().toString())

    public fun write(value: CharArray): Unit = write(value, 0, value.size)

    public fun write(value: CharArray, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.size - length) {
            throw IndexOutOfBoundsException()
        }
        var index = 0
        while (index < length) {
            write(value[offset + index].toString())
            index += 1
        }
    }

    public fun write(value: String, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.length - length) {
            throw IndexOutOfBoundsException()
        }
        write(value.substring(offset, offset + length))
    }

    public fun append(value: Char): StringWriter {
        write(value.toString())
        return this
    }

    public fun append(value: CharSequence?): StringWriter {
        write(value?.toString() ?: "null")
        return this
    }

    public fun append(value: CharSequence?, startIndex: Int, endIndex: Int): StringWriter {
        val text = value?.toString() ?: "null"
        if (startIndex < 0 || endIndex < startIndex || endIndex > text.length) {
            throw IndexOutOfBoundsException()
        }
        write(text.substring(startIndex, endIndex))
        return this
    }

    @KsSymbolName("__kk_string_writer_get_buffer")
    public external fun getBuffer(): StringBuffer

    @KsSymbolName("__kk_buffered_writer_flush")
    public external override fun flush(): Unit

    @KsSymbolName("__kk_buffered_writer_close_throwing")
    public external override fun close(): Unit

    @KsSymbolName("__kk_string_writer_to_string")
    public external override fun toString(): String
}
