package java.util.zip

/** Adler-32 checksum used by zlib streams. */
public class Adler32 : Checksum {
    private var a = 1
    private var b = 0

    override fun update(value: Int) {
        a = (a + (value and 0xFF)) % 65521
        b = (b + a) % 65521
    }

    override fun update(data: ByteArray, offset: Int, length: Int) {
        if (offset < 0 || length < 0 || offset > data.size - length) {
            throw IndexOutOfBoundsException()
        }
        var index = offset
        val end = offset + length
        while (index < end) {
            update(data[index].toInt())
            index++
        }
    }

    override fun getValue(): Long = ((b shl 16) or a).toLong() and 0xFFFFFFFFL

    override fun reset() {
        a = 1
        b = 0
    }
}
