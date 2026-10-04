import kotlinx.io.Buffer
import kotlinx.io.RawSink
import kotlinx.io.RawSource
import kotlinx.io.Source

fun copying(buffer: Buffer, other: Buffer, rawSource: RawSource, rawSink: RawSink): Source {
    buffer.copy()
    buffer.copyTo(other)
    buffer.copyTo(other, 0L, 1L)
    buffer.get(0L)
    buffer.indexOf(1)
    buffer.readAtMostTo(other, 1L)
    buffer.write(other, 1L)
    buffer.write(rawSource, 1L)
    buffer.readTo(rawSink, 1L)
    buffer.transferFrom(rawSource)
    buffer.transferTo(rawSink)
    rawSource.readAtMostTo(other, 1L)
    rawSink.write(other, 1L)
    rawSink.flush()
    rawSource.close()
    rawSink.close()
    buffer.use { it.clear() }
    return buffer.peek()
}
