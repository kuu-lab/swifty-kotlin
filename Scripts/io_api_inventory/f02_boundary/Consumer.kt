package f02boundaryconsumer

import f02boundary.*
import kotlinx.io.*
import kotlinx.io.bytestring.*
import java.lang.System

fun main() {
    println("initialization:" + initializationOrder)
    println("accessor:" + initialBytes.toHexString())
    var invocations = 0
    inspect { bytes ->
        invocations++
        println("inline-default:" + bytes.toHexString())
    }
    inspect(ByteString(1, 2)) { bytes ->
        invocations++
        println("inline-explicit:" + bytes.toHexString())
    }
    println("callbacks:" + invocations)
    try {
        inspect { throw IllegalStateException("from-consumer") }
    } catch (failure: IllegalStateException) {
        println("callback-throw:" + failure.message)
    }
    val callback = retainedCallback()
    val input = retainedInput()
    System.gc()
    println("retained-callback:" + callback())
    println("retained-input:" + input.read() + ":" + input.read())
    input.close()
    producerMain()
    println("initialization-once:" + initializationOrder)
}
