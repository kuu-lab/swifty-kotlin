package kuu2615shape.producer

import kotlinx.io.Buffer
import kotlinx.io.RawSource

public class ExternalRawSource : RawSource {
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
    override fun close() {}
}

public fun createRawSource(): RawSource = ExternalRawSource()
