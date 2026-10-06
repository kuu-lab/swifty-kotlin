import kotlinx.io.Buffer
import kotlinx.io.Sink
import kotlinx.io.Source
import kotlinx.io.bytestring.ByteString
import kotlinx.io.indexOf
import kotlinx.io.readByteString
import kotlinx.io.snapshot
import kotlinx.io.write

fun probe(buffer: Buffer, source: Source, sink: Sink, bytes: ByteString) {
    sink.write(bytes)
    sink.write(bytes, 1)
    sink.write(bytes, 1, 2)
    buffer.write(byteArrayOf(1, 2))
    source.readByteString()
    source.readByteString(1)
    source.indexOf(bytes)
    source.indexOf(bytes, 1)
    buffer.indexOf(bytes)
    buffer.indexOf(bytes, 1)
    buffer.indexOf(1.toByte())
    buffer.snapshot()
    buffer.copy()
}
