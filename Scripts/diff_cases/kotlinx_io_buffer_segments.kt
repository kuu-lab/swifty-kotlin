import kotlinx.io.*

fun pattern(count: Int): ByteArray {
    val bytes = ByteArray(count)
    var i = 0
    while (i < count) {
        bytes[i] = (i % 251).toByte()
        i += 1
    }
    return bytes
}

fun main() {
    val bytes = pattern(20000)
    val buffer = Buffer()
    buffer.write(bytes, 0, bytes.size)
    println(buffer.size)
    println(buffer.get(8191L))
    println(buffer.get(8192L))
    println(buffer.get(19999L))
    println(buffer.indexOf(17, 8190L, 8300L))
    val array = ByteArray(10000)
    println(buffer.readAtMostTo(array, 0, array.size))
    println(buffer.size)

    val copy = buffer.copy()
    val slice = Buffer()
    buffer.copyTo(slice, 8000L, 9000L)
    println(slice.size)
    println(slice.readByte())
    buffer.clear()
    buffer.writeByte(99)
    println(copy.readByte())
    println(buffer.readByte())

    val source = Buffer()
    source.write(bytes, 0, bytes.size)
    val moved = Buffer()
    moved.write(source, 9000L)
    println(source.size)
    println(moved.size)
    println(moved.get(8999L))
    println(source.readByte())
    moved.write(source, source.size)
    println(moved.size)
    println(source.exhausted())
    println(moved.get(9000L))

    val split = Buffer()
    split.write(bytes, 0, 8192)
    val prefix = Buffer()
    prefix.write(split, 100L)
    println(prefix.readAtMostTo(array, 0, array.size))
    val sharedPrefix = Buffer()
    sharedPrefix.write(split, 2000L)
    println(sharedPrefix.readAtMostTo(array, 0, array.size))
    println(split.get(0L))

    val compact = Buffer()
    compact.write(bytes, 0, 8000)
    compact.skip(7000L)
    val extra = Buffer()
    extra.write(bytes, 0, 3000)
    compact.write(extra, extra.size)
    println(compact.readAtMostTo(array, 0, array.size))
    println(compact.exhausted())

    val shared = Buffer()
    shared.write(bytes, 0, 8000)
    val preserved = shared.copy()
    shared.skip(7000L)
    extra.write(bytes, 0, 3000)
    shared.write(extra, extra.size)
    println(shared.readAtMostTo(array, 0, array.size))
    println(preserved.readByte())
    println(preserved.get(7998L))

    val self = Buffer()
    self.write(bytes, 0, 9000)
    self.copyTo(self, 8000L, 8500L)
    println(self.size)
    println(self.get(9000L))
    println(self.get(9499L))

    val boundary = Buffer()
    boundary.write(bytes, 0, 8191)
    boundary.writeShort((-12345).toShort())
    boundary.writeInt(-123456789)
    boundary.writeLong(Long.MIN_VALUE)
    boundary.skip(8191L)
    println(boundary.readShort())
    println(boundary.readInt())
    println(boundary.readLong())
    println(boundary.exhausted())

    val crossing = Buffer()
    crossing.write(byteArrayOf(1, 2, 3), 0, 3)
    val longBytes = Buffer()
    longBytes.writeLong(0x0405060708090a0bL)
    longBytes.copyTo(crossing)
    println(crossing.readLong())
    println(crossing.readShort())
    println(crossing.readByte())
}
