// IO_API_VALIDATION_PROBE: probe:KUU-2612:sink-rawsink-kotlin-reference

import kotlinx.io.RawSink
import kotlinx.io.Sink

fun main() {
    println("sink.sealed=${Sink::class.isSealed}")
    println("rawSink.sealed=${RawSink::class.isSealed}")
    println("sink.parents=${Sink::class.java.interfaces.map { it.name }.sorted().joinToString(",")}")
    println("rawSink.parents=${RawSink::class.java.interfaces.map { it.name }.sorted().joinToString(",")}")
}
