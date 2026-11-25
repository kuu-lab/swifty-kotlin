/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/encoding/Decoding.kt.
 */

package kotlinx.serialization.encoding

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.modules.*

public interface Decoder {
    public val serializersModule: SerializersModule

    @ExperimentalSerializationApi
    public fun decodeNotNullMark(): Boolean

    @ExperimentalSerializationApi
    public fun decodeNull(): Nothing?

    public fun decodeBoolean(): Boolean

    public fun decodeByte(): Byte

    public fun decodeShort(): Short

    public fun decodeChar(): Char

    public fun decodeInt(): Int

    public fun decodeLong(): Long

    public fun decodeFloat(): Float

    public fun decodeDouble(): Double

    public fun decodeString(): String

    public fun decodeEnum(enumDescriptor: SerialDescriptor): Int

    public fun decodeInline(descriptor: SerialDescriptor): Decoder

    public fun beginStructure(descriptor: SerialDescriptor): CompositeDecoder

    public fun <T : Any?> decodeSerializableValue(deserializer: DeserializationStrategy<T>): T =
        deserializer.deserialize(this)

    @ExperimentalSerializationApi
    public fun <T : Any> decodeNullableSerializableValue(deserializer: DeserializationStrategy<T?>): T? = decodeIfNullable(deserializer) {
        decodeSerializableValue(deserializer)
    }
}

@OptIn(ExperimentalSerializationApi::class)
internal inline fun <T : Any> Decoder.decodeIfNullable(deserializer: DeserializationStrategy<T?>, block: () -> T?): T? {
    val isNullabilitySupported = deserializer.descriptor.isNullable
    return if (isNullabilitySupported || decodeNotNullMark()) block() else decodeNull()
}

public interface CompositeDecoder {

    public companion object {
        public const val DECODE_DONE: Int = -1

        public const val UNKNOWN_NAME: Int = -3
    }

    public val serializersModule: SerializersModule

    public fun endStructure(descriptor: SerialDescriptor)

    @ExperimentalSerializationApi
    public fun decodeSequentially(): Boolean = false

    public fun decodeElementIndex(descriptor: SerialDescriptor): Int

    public fun decodeCollectionSize(descriptor: SerialDescriptor): Int = -1

    public fun decodeBooleanElement(descriptor: SerialDescriptor, index: Int): Boolean

    public fun decodeByteElement(descriptor: SerialDescriptor, index: Int): Byte

    public fun decodeCharElement(descriptor: SerialDescriptor, index: Int): Char

    public fun decodeShortElement(descriptor: SerialDescriptor, index: Int): Short

    public fun decodeIntElement(descriptor: SerialDescriptor, index: Int): Int

    public fun decodeLongElement(descriptor: SerialDescriptor, index: Int): Long

    public fun decodeFloatElement(descriptor: SerialDescriptor, index: Int): Float

    public fun decodeDoubleElement(descriptor: SerialDescriptor, index: Int): Double

    public fun decodeStringElement(descriptor: SerialDescriptor, index: Int): String

    public fun decodeInlineElement(
        descriptor: SerialDescriptor,
        index: Int
    ): Decoder

    public fun <T : Any?> decodeSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        deserializer: DeserializationStrategy<T>,
        previousValue: T? = null
    ): T

    @ExperimentalSerializationApi
    public fun <T : Any> decodeNullableSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        deserializer: DeserializationStrategy<T?>,
        previousValue: T? = null
    ): T?
}

public inline fun <T> Decoder.decodeStructure(
    descriptor: SerialDescriptor,
    crossinline block: CompositeDecoder.() -> T
): T {
    val composite = beginStructure(descriptor)
    val result = composite.block()
    composite.endStructure(descriptor)
    return result
}
