/*
 * Copyright 2017-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package kotlinx.serialization.json

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerializationException
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.StringFormat
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.encoding.CompositeEncoder
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.modules.EmptySerializersModule
import kotlinx.serialization.modules.SerializersModule
import kotlinx.serialization.serializer

/**
 * Entry point for JSON serialization.
 */
public abstract class Json : StringFormat {
    public override val serializersModule: SerializersModule
        get() = EmptySerializersModule()

    /** Encodes [value] using the supplied [serializer]. */
    public override fun <T> encodeToString(serializer: SerializationStrategy<T>, value: T): String {
        val output = StringBuilder()
        serializer.serialize(JsonEncoder(serializersModule) { output.append(it) }, value)
        return output.toString()
    }

    /** Encodes [value] using its generated or registered serializer. */
    public inline fun <reified T> encodeToString(value: T): String =
        encodeToString(serializer<T>(), value)

    /** Decodes [string] using the supplied [deserializer]. */
    public override fun <T> decodeFromString(deserializer: DeserializationStrategy<T>, string: String): T =
        deserializer.deserialize(JsonDecoder(JsonParser(string).parse(), serializersModule))

    /** Decodes [string] using the generated or registered deserializer. */
    public inline fun <reified T> decodeFromString(string: String): T =
        decodeFromString(serializer<T>(), string)

    public fun parseToJsonElement(string: String): JsonElement = JsonParser(string).parse()

    public companion object Default : Json()
}

private class JsonEncoder(
    override val serializersModule: SerializersModule,
    private val writeValue: (String) -> Unit
) : Encoder {
    override fun encodeNull() = writeValue("null")
    override fun encodeBoolean(value: Boolean) = writeValue(value.toString())
    override fun encodeByte(value: Byte) = writeValue(value.toString())
    override fun encodeShort(value: Short) = writeValue(value.toString())
    override fun encodeChar(value: Char) = writeValue(value.toString().toJsonQuotedString())
    override fun encodeInt(value: Int) = writeValue(value.toString())
    override fun encodeLong(value: Long) = writeValue(value.toString())
    override fun encodeFloat(value: Float) = writeValue(value.toString())
    override fun encodeDouble(value: Double) = writeValue(value.toString())
    override fun encodeString(value: String) = writeValue(value.toJsonQuotedString())

    override fun encodeEnum(enumDescriptor: SerialDescriptor, index: Int) =
        encodeString(enumDescriptor.getElementName(index))

    override fun encodeInline(descriptor: SerialDescriptor): Encoder = this

    override fun beginStructure(descriptor: SerialDescriptor): CompositeEncoder {
        writeValue("{")
        return JsonCompositeEncoder(this, descriptor)
    }

    fun beginElement(descriptor: SerialDescriptor, index: Int, first: Boolean) {
        if (!first) writeValue(",")
        writeValue(descriptor.getElementName(index).toJsonQuotedString())
        writeValue(":")
    }

    fun elementEncoder(): Encoder = JsonEncoder(serializersModule, writeValue)
    fun endStructure() = writeValue("}")
}

private class JsonCompositeEncoder(
    private val parent: JsonEncoder,
    private val descriptor: SerialDescriptor
) : CompositeEncoder {
    override val serializersModule: SerializersModule = parent.serializersModule
    private var first = true

    override fun endStructure(descriptor: SerialDescriptor) {
        parent.endStructure()
    }

    private fun start(index: Int) {
        parent.beginElement(descriptor, index, first)
        first = false
    }

    override fun encodeBooleanElement(descriptor: SerialDescriptor, index: Int, value: Boolean) {
        start(index); parent.elementEncoder().encodeBoolean(value)
    }

    override fun encodeByteElement(descriptor: SerialDescriptor, index: Int, value: Byte) {
        start(index); parent.elementEncoder().encodeByte(value)
    }

    override fun encodeShortElement(descriptor: SerialDescriptor, index: Int, value: Short) {
        start(index); parent.elementEncoder().encodeShort(value)
    }

    override fun encodeCharElement(descriptor: SerialDescriptor, index: Int, value: Char) {
        start(index); parent.elementEncoder().encodeChar(value)
    }

    override fun encodeIntElement(descriptor: SerialDescriptor, index: Int, value: Int) {
        start(index); parent.elementEncoder().encodeInt(value)
    }

    override fun encodeLongElement(descriptor: SerialDescriptor, index: Int, value: Long) {
        start(index); parent.elementEncoder().encodeLong(value)
    }

    override fun encodeFloatElement(descriptor: SerialDescriptor, index: Int, value: Float) {
        start(index); parent.elementEncoder().encodeFloat(value)
    }

    override fun encodeDoubleElement(descriptor: SerialDescriptor, index: Int, value: Double) {
        start(index); parent.elementEncoder().encodeDouble(value)
    }

    override fun encodeStringElement(descriptor: SerialDescriptor, index: Int, value: String) {
        start(index); parent.elementEncoder().encodeString(value)
    }

    override fun encodeInlineElement(descriptor: SerialDescriptor, index: Int): Encoder {
        start(index)
        return parent.elementEncoder()
    }

    override fun <T> encodeSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        serializer: SerializationStrategy<T>,
        value: T
    ) {
        start(index)
        serializer.serialize(parent.elementEncoder(), value)
    }

    override fun <T : Any> encodeNullableSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        serializer: SerializationStrategy<T>,
        value: T?
    ) {
        start(index)
        if (value == null) parent.elementEncoder().encodeNull()
        else serializer.serialize(parent.elementEncoder(), value)
    }
}

private class JsonDecoder(
    private val value: JsonElement,
    override val serializersModule: SerializersModule
) : Decoder {
    override fun decodeNotNullMark(): Boolean = value !== JsonNull

    override fun decodeNull(): Nothing? {
        if (value !== JsonNull) throw SerializationException("Expected null, found $value")
        return null
    }

    override fun decodeBoolean(): Boolean = primitive().boolean
    override fun decodeByte(): Byte = primitive().content.toByte()
    override fun decodeShort(): Short = primitive().content.toShort()
    override fun decodeChar(): Char = primitive().content.single()
    override fun decodeInt(): Int = primitive().content.toInt()
    override fun decodeLong(): Long = primitive().content.toLong()
    override fun decodeFloat(): Float = primitive().content.toFloat()
    override fun decodeDouble(): Double = primitive().content.toDouble()
    override fun decodeString(): String = primitive().content
    override fun decodeEnum(enumDescriptor: SerialDescriptor): Int =
        enumDescriptor.getElementIndex(decodeString()).also {
            if (it < 0) throw SerializationException("Unknown enum value for ${enumDescriptor.serialName}")
        }

    override fun decodeInline(descriptor: SerialDescriptor): Decoder = this

    override fun beginStructure(descriptor: SerialDescriptor): CompositeDecoder {
        val objectValue = value as? JsonObject
            ?: throw SerializationException("Expected JSON object for ${descriptor.serialName}")
        return JsonCompositeDecoder(objectValue, serializersModule)
    }

    private fun primitive(): JsonPrimitive = value as? JsonPrimitive
        ?: throw SerializationException("Expected JSON primitive, found $value")
}

private class JsonCompositeDecoder(
    private val value: JsonObject,
    override val serializersModule: SerializersModule
) : CompositeDecoder {
    private var nextIndex = 0

    override fun endStructure(descriptor: SerialDescriptor) {}

    override fun decodeElementIndex(descriptor: SerialDescriptor): Int {
        while (nextIndex < descriptor.elementsCount) {
            val index = nextIndex++
            if (value.containsKey(descriptor.getElementName(index))) return index
        }
        return CompositeDecoder.DECODE_DONE
    }

    private fun element(descriptor: SerialDescriptor, index: Int): JsonElement =
        value[descriptor.getElementName(index)]
            ?: throw SerializationException("Missing JSON element '${descriptor.getElementName(index)}'")

    override fun decodeBooleanElement(descriptor: SerialDescriptor, index: Int): Boolean =
        JsonDecoder(element(descriptor, index), serializersModule).decodeBoolean()

    override fun decodeByteElement(descriptor: SerialDescriptor, index: Int): Byte =
        JsonDecoder(element(descriptor, index), serializersModule).decodeByte()

    override fun decodeShortElement(descriptor: SerialDescriptor, index: Int): Short =
        JsonDecoder(element(descriptor, index), serializersModule).decodeShort()

    override fun decodeCharElement(descriptor: SerialDescriptor, index: Int): Char =
        JsonDecoder(element(descriptor, index), serializersModule).decodeChar()

    override fun decodeIntElement(descriptor: SerialDescriptor, index: Int): Int =
        JsonDecoder(element(descriptor, index), serializersModule).decodeInt()

    override fun decodeLongElement(descriptor: SerialDescriptor, index: Int): Long =
        JsonDecoder(element(descriptor, index), serializersModule).decodeLong()

    override fun decodeFloatElement(descriptor: SerialDescriptor, index: Int): Float =
        JsonDecoder(element(descriptor, index), serializersModule).decodeFloat()

    override fun decodeDoubleElement(descriptor: SerialDescriptor, index: Int): Double =
        JsonDecoder(element(descriptor, index), serializersModule).decodeDouble()

    override fun decodeStringElement(descriptor: SerialDescriptor, index: Int): String =
        JsonDecoder(element(descriptor, index), serializersModule).decodeString()

    override fun decodeInlineElement(descriptor: SerialDescriptor, index: Int): Decoder =
        JsonDecoder(element(descriptor, index), serializersModule)

    override fun <T> decodeSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        deserializer: DeserializationStrategy<T>,
        previousValue: T?
    ): T = deserializer.deserialize(JsonDecoder(element(descriptor, index), serializersModule))

    override fun <T : Any> decodeNullableSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        deserializer: DeserializationStrategy<T?>,
        previousValue: T?
    ): T? {
        val child = element(descriptor, index)
        if (child === JsonNull) return null
        return deserializer.deserialize(JsonDecoder(child, serializersModule))
    }
}
