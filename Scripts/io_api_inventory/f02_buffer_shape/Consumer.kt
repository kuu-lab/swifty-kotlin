package io.gate.buffer.consumer

import io.gate.buffer.producer.newBuffer
import kotlinx.io.Buffer
import kotlinx.io.Sink
import kotlinx.io.Source

fun main() {
    val buffer: Buffer = newBuffer()
    val sink: Sink = buffer
    val source: Source = buffer
    val erased: Any = buffer

    check(sink === buffer)
    check(source === buffer)
    check(erased is Sink)
    check(erased is Source)
    check(buffer.size == 0L)
    check(source.exhausted())

    println("BUFFER:interfaces=sink+source,size=${buffer.size},exhausted=${source.exhausted()}")
}
