package kuu2615shape.combined

import kotlin.AutoCloseable
import kotlinx.io.Buffer
import kotlinx.io.RawSource
import kotlinx.io.Source

class ExternalRawSource : RawSource {
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
    override fun close() {}
}

fun main() {
    val source: Source = Buffer()
    val raw: RawSource = source
    val closeable: AutoCloseable = raw
    closeable.close()
    println("source-as-raw=${raw === source}")

    val external: RawSource = ExternalRawSource()
    println("external-raw-read=${external.readAtMostTo(Buffer(), 1L)}")
}
