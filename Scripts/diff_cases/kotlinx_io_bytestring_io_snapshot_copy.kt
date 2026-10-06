import kotlinx.io.Buffer
import kotlinx.io.bytestring.ByteString
import kotlinx.io.readByteString
import kotlinx.io.snapshot
import kotlinx.io.write

fun main() {
    println(Buffer().snapshot())
    val data = ByteArray(17000)
    var i = 0
    while (i < data.size) {
        data[i] = (i % 251).toByte()
        i++
    }
    val bytes = ByteString(data)
    val buffer = Buffer()
    buffer.write(bytes)
    println(buffer.size)
    val snapshot = buffer.snapshot()
    println(snapshot == bytes)
    println(buffer.size)
    val copy = buffer.copy()
    buffer.skip(8191)
    val partialSnapshot = buffer.snapshot()
    println(partialSnapshot == bytes.substring(8191))
    println(buffer.readByteString(8194) == bytes.substring(8191, 16585))
    buffer.clear()
    buffer.write(ByteString(byteArrayOf(99)))
    println(copy.readByteString() == bytes)
    println(copy.size)
    println(snapshot == bytes)
    println(partialSnapshot == bytes.substring(8191))
    println(buffer.readByteString())
    println(Buffer().copy().size)
}
