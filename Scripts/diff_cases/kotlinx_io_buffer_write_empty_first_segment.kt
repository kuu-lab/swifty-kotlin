import kotlinx.io.*

// KUU-2652: the first write into an empty Buffer goes through writableSegment's
// `tail == null` branch; head/tail must start as null, not as an unseeded sentinel.
fun main() {
    val buffer = Buffer()
    println(buffer.size)
    buffer.writeByte(1)
    buffer.writeShort(2)
    buffer.writeInt(3)
    buffer.writeLong(4L)
    println(buffer.size)
    println(buffer.readByte())
    println(buffer.readShort())
    println(buffer.readInt())
    println(buffer.readLong())

    val source = Buffer()
    source.writeByte(7)
    discardingSink().write(source, 1L)
    println(source.exhausted())
}
