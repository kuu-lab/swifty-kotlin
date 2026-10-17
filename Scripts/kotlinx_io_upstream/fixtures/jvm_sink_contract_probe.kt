package kotlinx.io.contractprobe

import java.io.IOException
import java.nio.charset.Charset
import kotlinx.io.Buffer
import kotlinx.io.RawSink
import kotlinx.io.buffered
import kotlinx.io.writeString

private class NoopRawSink : RawSink {
    override fun write(source: Buffer, byteCount: Long) {}
    override fun flush() {}
    override fun close() {}
}

private class FailingRawSink : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        throw IOException("synthetic sink failure")
    }

    override fun flush() {}
    override fun close() {}
}

private inline fun <reified T : Throwable> expectException(label: String, block: () -> Unit): String {
    val failure = try {
        block()
        null
    } catch (thrown: Throwable) {
        thrown
    } ?: throw IllegalStateException("$label did not throw")
    check(failure is T) {
        "$label threw ${failure::class.qualifiedName}, expected ${T::class.qualifiedName}"
    }
    return "$label=${failure::class.qualifiedName}"
}

private fun verifyMissingExceptionIsRejected() {
    val failure = try {
        expectException<IllegalStateException>("missing-exception") {}
        null
    } catch (thrown: IllegalStateException) {
        thrown
    }
    check(failure?.message == "missing-exception did not throw")
}

fun verifySinkWriteStringContracts(): String {
    verifyMissingExceptionIsRejected()
    val charset = Charset.forName("utf-32be")
    val observed = listOf(
        expectException<IndexOutOfBoundsException>("negative-start") {
            Buffer().writeString("abc", charset, -1, 1)
        },
        expectException<IllegalArgumentException>("reversed-range") {
            Buffer().writeString("abc", charset, 2, 1)
        },
        expectException<IllegalStateException>("closed-sink") {
            val sink = NoopRawSink().buffered()
            sink.close()
            sink.writeString("a", charset)
        },
        expectException<IOException>("io-failure") {
            FailingRawSink().buffered().writeString("a".repeat(4096), charset)
        },
    )
    return observed.joinToString(";")
}
