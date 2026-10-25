package java.util.zip

/** CRC-32 checksum using the polynomial specified by RFC 1952. */
public class CRC32 : Checksum {
    private var crc = -1

    override fun update(value: Int) {
        crc = crc xor (value and 0xFF)
        var bit = 0
        while (bit < 8) {
            crc = if ((crc and 1) != 0) (crc ushr 1) xor -306674912 else crc ushr 1
            bit++
        }
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

    override fun getValue(): Long = (crc xor -1).toLong() and 0xFFFFFFFFL

    override fun reset() {
        crc = -1
    }
}
