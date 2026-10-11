@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package kuu1763publicproducer
import kotlinx.io.*
import kotlinx.io.bytestring.*
import platform.Foundation.*
public fun copiedData(bytes: ByteArray): NSData = ByteString(bytes).toNSData()
public fun copiedBytes(data: NSData): ByteString = data.toByteString()
public fun inputFromSource(source: Source): NSInputStream = source.asNSInputStream()
public fun outputFromSink(sink: Sink): NSOutputStream = sink.asNSOutputStream()
public fun sourceFromInput(input: NSInputStream): RawSource = input.asSource()
public fun sinkFromOutput(output: NSOutputStream): RawSink = output.asSink()

public fun errorAndPartialContracts() { kuu1763errorcontracts.runErrorAndPartialContracts() }
