import kotlinx.io.SinkTestObservations

fun main() {
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStream()]")
    try {
        kotlinx.io.BufferSinkTestJVM().outputStream()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStream()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStream()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStream()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamBounds()]")
    try {
        kotlinx.io.BufferSinkTestJVM().outputStreamBounds()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamBounds()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamBounds()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamBounds()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamClosesSink()]")
    try {
        kotlinx.io.BufferSinkTestJVM().outputStreamClosesSink()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamClosesSink()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamClosesSink()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStreamClosesSink()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()]")
    try {
        kotlinx.io.BufferSinkTestJVM().writeLargeNioBufferWritesAllData()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBuffer()]")
    try {
        kotlinx.io.BufferSinkTestJVM().writeNioBuffer()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBuffer()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBuffer()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBuffer()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBufferToClosedSink()]")
    try {
        kotlinx.io.BufferSinkTestJVM().writeNioBufferToClosedSink()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBufferToClosedSink()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBufferToClosedSink()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeNioBufferToClosedSink()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeStringWithCharset()]")
    try {
        kotlinx.io.BufferSinkTestJVM().writeStringWithCharset()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeStringWithCharset()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeStringWithCharset()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeStringWithCharset()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeSubstringWithCharset()]")
    try {
        kotlinx.io.BufferSinkTestJVM().writeSubstringWithCharset()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeSubstringWithCharset()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeSubstringWithCharset()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeSubstringWithCharset()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeToClosedOutputStream()]")
    try {
        kotlinx.io.BufferSinkTestJVM().writeToClosedOutputStream()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeToClosedOutputStream()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeToClosedOutputStream()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeToClosedOutputStream()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeUtf8SubstringWithCharset()]")
    try {
        kotlinx.io.BufferSinkTestJVM().writeUtf8SubstringWithCharset()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeUtf8SubstringWithCharset()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeUtf8SubstringWithCharset()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:writeUtf8SubstringWithCharset()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStream()]")
    try {
        kotlinx.io.RealSinkTestJVM().outputStream()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStream()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStream()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStream()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamBounds()]")
    try {
        kotlinx.io.RealSinkTestJVM().outputStreamBounds()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamBounds()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamBounds()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamBounds()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamClosesSink()]")
    try {
        kotlinx.io.RealSinkTestJVM().outputStreamClosesSink()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamClosesSink()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamClosesSink()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:outputStreamClosesSink()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()]")
    try {
        kotlinx.io.RealSinkTestJVM().writeLargeNioBufferWritesAllData()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeLargeNioBufferWritesAllData()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBuffer()]")
    try {
        kotlinx.io.RealSinkTestJVM().writeNioBuffer()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBuffer()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBuffer()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBuffer()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBufferToClosedSink()]")
    try {
        kotlinx.io.RealSinkTestJVM().writeNioBufferToClosedSink()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBufferToClosedSink()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBufferToClosedSink()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeNioBufferToClosedSink()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeStringWithCharset()]")
    try {
        kotlinx.io.RealSinkTestJVM().writeStringWithCharset()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeStringWithCharset()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeStringWithCharset()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeStringWithCharset()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeSubstringWithCharset()]")
    try {
        kotlinx.io.RealSinkTestJVM().writeSubstringWithCharset()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeSubstringWithCharset()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeSubstringWithCharset()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeSubstringWithCharset()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeToClosedOutputStream()]")
    try {
        kotlinx.io.RealSinkTestJVM().writeToClosedOutputStream()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeToClosedOutputStream()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeToClosedOutputStream()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeToClosedOutputStream()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    SinkTestObservations.reset()
    println("KIO_9233296942e5e07552d72007 BEGIN [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeUtf8SubstringWithCharset()]")
    try {
        kotlinx.io.RealSinkTestJVM().writeUtf8SubstringWithCharset()
        println("KIO_9233296942e5e07552d72007_OBS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeUtf8SubstringWithCharset()] " + SinkTestObservations.toJson())
        println("KIO_9233296942e5e07552d72007 PASS [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeUtf8SubstringWithCharset()]")
    } catch (failure: Throwable) {
        println("KIO_9233296942e5e07552d72007 FAIL [engine:kswiftk-macos-native]/[class:kotlinx.io.RealSinkTestJVM]/[method:writeUtf8SubstringWithCharset()]")
        println("KIO_9233296942e5e07552d72007 EXCEPTION " + failure::class.qualifiedName)
    }
    println("KIO_9233296942e5e07552d72007_CONTRACT_PROBE " + kotlinx.io.contractprobe.verifySinkWriteStringContracts())
}
