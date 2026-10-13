@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

import com.typesafe.config.ConfigFactory
import java.time.Duration
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.*
import kotlinx.serialization.cbor.Cbor
import kotlinx.serialization.hocon.Hocon
import kotlinx.serialization.hocon.serializers.JavaDurationSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.io.decodeFromSource
import kotlinx.serialization.json.io.decodeSourceToSequence
import kotlinx.serialization.json.io.encodeToSink
import kotlinx.serialization.json.okio.decodeFromBufferedSource
import kotlinx.serialization.json.okio.decodeBufferedSourceToSequence
import kotlinx.serialization.json.okio.encodeToBufferedSink
import kotlinx.serialization.properties.Properties
import kotlinx.serialization.protobuf.ProtoBuf
import kotlinx.serialization.protobuf.schema.ProtoBufSchemaGenerator
import kotlinx.io.Buffer as IoBuffer
import kotlinx.io.writeString
import okio.Buffer as OkioBuffer

@Serializable
data class Entry(val name: String, val value: Int = 7)

fun main() {
    val serializer = Entry.serializer()
    val value = Entry("sample", 42)
    val descriptor = serializer.descriptor
    check(descriptor.serialName == "Entry" && descriptor.elementsCount == 2)
    check(descriptor.getElementName(1) == "value" && descriptor.isElementOptional(1))
    println("core: generated descriptor, names, defaults")

    val json = Json.encodeToString(serializer, value)
    check(json == "{\"name\":\"sample\",\"value\":42}")
    check(Json.decodeFromString(serializer, json) == value)
    check(Json.decodeFromString(serializer, "{\"name\":\"default\"}") == Entry("default"))
    val tree = buildJsonObject { put("value", 42); put("nullable", JsonNull) }
    check(tree.toString() == "{\"value\":42,\"nullable\":null}")
    check(runCatching { Json.decodeFromString(serializer, "{") }.isFailure)
    println("json: round trip, default, tree, malformed input")

    val cbor = Cbor.encodeToByteArray(serializer, value)
    check(Cbor.decodeFromByteArray(serializer, cbor) == value)
    check(runCatching { Cbor.decodeFromByteArray(serializer, byteArrayOf()) }.isFailure)
    println("cbor: round trip, truncated input")

    val proto = ProtoBuf.encodeToByteArray(serializer, value)
    check(ProtoBuf.decodeFromByteArray(serializer, proto) == value)
    val schema = ProtoBufSchemaGenerator.generateSchemaText(descriptor, "reference")
    check(schema.contains("message Entry") && schema.contains("string name") && schema.contains("int32 value"))
    println("protobuf: round trip, generated schema")

    val typed = Properties.encodeToMap(serializer, value)
    check(typed["name"] == "sample" && typed["value"] == 42)
    check(Properties.decodeFromMap(serializer, typed) == value)
    val strings = Properties.encodeToStringMap(serializer, value)
    check(strings == mapOf("name" to "sample", "value" to "42"))
    check(Properties.decodeFromStringMap(serializer, strings) == value)
    println("properties: typed and string maps")

    val io = IoBuffer()
    Json.encodeToSink(serializer, value, io)
    check(Json.decodeFromSource(serializer, io) == value)
    val ioSequenceBuffer = IoBuffer().apply { writeString("1 2 {") }
    val ioIterator = Json.decodeSourceToSequence(ioSequenceBuffer, Int.serializer()).iterator()
    check(ioIterator.next() == 1 && ioIterator.next() == 2)
    check(runCatching { ioIterator.next() }.isFailure)
    ioSequenceBuffer.close()
    println("json-io: round trip, lazy failure, caller closes source")

    val okio = OkioBuffer()
    Json.encodeToBufferedSink(serializer, value, okio)
    check(Json.decodeFromBufferedSource(serializer, okio) == value)
    val okioSequenceBuffer = OkioBuffer().writeUtf8("3 4 {")
    val okioIterator = Json.decodeBufferedSourceToSequence(okioSequenceBuffer, Int.serializer()).iterator()
    check(okioIterator.next() == 3 && okioIterator.next() == 4)
    check(runCatching { okioIterator.next() }.isFailure)
    okioSequenceBuffer.close()
    println("json-okio: round trip, lazy failure, caller closes source")

    val config = Hocon.encodeToConfig(serializer, value)
    check(config.getString("name") == "sample" && config.getInt("value") == 42)
    check(Hocon.decodeFromConfig(serializer, config) == value)
    val durations = MapSerializer(String.serializer(), JavaDurationSerializer)
    val durationConfig = ConfigFactory.parseString("delay = 2 m")
    check(Hocon.decodeFromConfig(durations, durationConfig) == mapOf("delay" to Duration.ofMinutes(2)))
    val encodedDuration = Hocon.encodeToConfig(durations, mapOf("delay" to Duration.ofMinutes(2)))
    check(encodedDuration.getDuration("delay") == Duration.ofMinutes(2))
    println("hocon: Config backend, Java duration")
}
