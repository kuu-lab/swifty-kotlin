package kotlinx.io

import java.io.InputStream
import java.nio.ByteBuffer

fun runKuu2563ApiContractProbe() {
    val buffer = Buffer()
    val source: Source = buffer
    val input: InputStream = source.asInputStream()
    check(input.available() == 0)
    check(input.read() == -1)
    check(input.read(ByteArray(1), 0, 1) == -1)

    val boundsBuffer = Buffer()
    boundsBuffer.writeString("a")
    val boundsSource: Source = boundsBuffer
    val boundsInput: InputStream = boundsSource.asInputStream()
    var boundsFailure: IllegalArgumentException? = null
    try {
        boundsInput.read(ByteArray(1), 1, 1)
    } catch (expected: IllegalArgumentException) {
        boundsFailure = expected
    }
    check(boundsFailure != null)
    check(boundsInput.read() == 'a'.code)

    val destination = ByteBuffer.allocate(1)
    val byteCount: Int = source.readAtMostTo(destination)
    check(byteCount == -1)
    check(destination.position() == 0)
    check(destination.limit() == destination.capacity())

    val closedSource = SourceFactory.REAL_BUFFERED_SOURCE.pipe().source
    closedSource.close()
    val failure = try {
        closedSource.readAtMostTo(ByteBuffer.allocate(1))
        null
    } catch (expected: IllegalStateException) {
        expected
    }
    check(failure != null)
    println("KUU2563_API_CONTRACT_PROBE_PASS Source.asInputStream:InputStream bounds:IllegalArgumentException:no-consumption Source.readAtMostTo:ByteBuffer->Int closedSource:IllegalStateException")
}
