import kotlinx.io.Buffer
import kotlinx.io.Sink
import kotlinx.io.Source
import kotlinx.io.bytestring.ByteString
import kotlinx.io.readByteString
import kotlinx.io.snapshot
import kotlinx.io.write

fun main() {
    val buffer = Buffer()
    val sink: Sink = buffer
    val bytes = ByteString(byteArrayOf(0, 65, -1, 66, 67))
    sink.write(bytes)
    sink.write(bytes, 1, 4)
    sink.write(bytes, 4)
    sink.write(bytes, 2, 2)
    sink.write(ByteString())
    // Importing write(ByteString) must not hide the ByteArray members.
    buffer.write(byteArrayOf(68))
    sink.write(byteArrayOf(69, 70), 1)
    println(buffer.snapshot())
    val source: Source = buffer
    println(source.readByteString(0))
    println(source.readByteString(3))
    println(buffer.size)
    println(source.readByteString())
    println(source.exhausted())
    println(source.readByteString())
}
