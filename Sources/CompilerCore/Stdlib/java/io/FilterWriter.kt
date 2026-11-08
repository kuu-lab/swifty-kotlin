package java.io

public abstract class FilterWriter(protected val out: Writer) : Writer() {
    public override fun write(value: String): Unit = out.write(value)

    public fun write(value: Int): Unit = out.write(value.toChar().toString())

    public fun write(value: CharArray): Unit = write(value, 0, value.size)

    public fun write(value: CharArray, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.size - length) {
            throw IndexOutOfBoundsException()
        }
        var index = 0
        while (index < length) {
            out.write(value[offset + index].toString())
            index += 1
        }
    }

    public fun write(value: String, offset: Int, length: Int): Unit {
        if (offset < 0 || length < 0 || offset > value.length - length) {
            throw IndexOutOfBoundsException()
        }
        out.write(value.substring(offset, offset + length))
    }

    public override fun flush(): Unit = out.flush()

    public override fun close(): Unit = out.close()
}
