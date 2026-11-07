package java.io

public class PushbackReader(`in`: Reader) : FilterReader(`in`) {
    private val pushback = ArrayList<Char>()
    private var closed: Boolean = false

    public constructor(`in`: Reader, size: Int) : this(`in`) {
        if (size <= 0) throw IllegalArgumentException("size <= 0")
    }

    public fun unread(value: Int): Unit {
        checkOpen()
        pushback.add(0, value.toChar())
    }

    public fun unread(value: CharArray): Unit = unread(value, 0, value.size)

    public fun unread(value: CharArray, offset: Int, length: Int): Unit {
        checkOpen()
        if (offset < 0 || length < 0 || offset > value.size - length) {
            throw IndexOutOfBoundsException()
        }
        var i = length - 1
        while (i >= 0) {
            pushback.add(0, value[offset + i])
            i -= 1
        }
    }

    public fun unread(value: String): Unit = unread(value, 0, value.length)

    public fun unread(value: String, offset: Int, length: Int): Unit {
        checkOpen()
        if (offset < 0 || length < 0 || offset > value.length - length) {
            throw IndexOutOfBoundsException()
        }
        var i = length - 1
        while (i >= 0) {
            pushback.add(0, value[offset + i])
            i -= 1
        }
    }

    public override fun read(buffer: CharArray, offset: Int, length: Int): Int {
        checkOpen()
        if (offset < 0 || length < 0 || offset > buffer.size - length) {
            throw IndexOutOfBoundsException()
        }
        if (length == 0) return 0
        var copied = 0
        while (copied < length && pushback.isNotEmpty()) {
            buffer[offset + copied] = pushback.removeAt(0)
            copied += 1
        }
        if (copied < length) {
            val n = super.read(buffer, offset + copied, length - copied)
            if (n > 0) copied += n
            else if (copied == 0) return n
        }
        return copied
    }

    public override fun read(): Int {
        checkOpen()
        if (pushback.isNotEmpty()) return pushback.removeAt(0).code
        return super.read()
    }

    public override fun close(): Unit {
        closed = true
        super.close()
    }

    private fun checkOpen(): Unit {
        if (closed) throw IOException()
    }
}
