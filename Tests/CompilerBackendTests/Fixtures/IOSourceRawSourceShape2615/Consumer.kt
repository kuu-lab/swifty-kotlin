package kuu2615shape.consumer

import kotlin.AutoCloseable
import kotlinx.io.Buffer
import kotlinx.io.RawSource
import kotlinx.io.Source
import kuu2615shape.producer.createRawSource

fun main() {
    val imported: RawSource = createRawSource()
    val closeable: AutoCloseable = imported
    closeable.close()
    println("imported-raw-read=${imported.readAtMostTo(Buffer(), 1L)}")

    val source: Source = Buffer()
    val raw: RawSource = source
    println("source-is-closeable=${raw is AutoCloseable}")
}
