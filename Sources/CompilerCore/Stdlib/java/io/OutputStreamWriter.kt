package java.io

public open class OutputStreamWriter : Writer {
    private val out: OutputStream
    private val charset: Charset
    private var closed: Boolean = false

    public constructor(out: OutputStream) {
        this.out = out
        this.charset = Charsets.UTF_8
    }

    public constructor(out: OutputStream, charset: Charset) {
        this.out = out
        this.charset = charset
    }

    public override fun write(value: String): Unit {
        checkOpen()
        out.write(value.encodeToByteArray(charset))
    }

    public fun write(value: Int): Unit = write(value.toChar().toString())

    public fun write(value: CharArray): Unit = write(String(value))

    public fun write(value: CharArray, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.size - length) {
            throw IndexOutOfBoundsException()
        }
        write(String(value, offset, length))
    }

    public fun write(value: String, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.length - length) {
            throw IndexOutOfBoundsException()
        }
        write(value.substring(offset, offset + length))
    }

    public fun append(value: CharSequence?): OutputStreamWriter {
        write(value?.toString() ?: "null")
        return this
    }

    public override fun flush(): Unit {
        checkOpen()
        out.flush()
    }

    public override fun close(): Unit {
        if (!closed) {
            closed = true
            out.close()
        }
    }

    private fun checkOpen(): Unit {
        if (closed) throw IOException()
    }
}
