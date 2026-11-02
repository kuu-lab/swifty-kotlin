/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/encoding/Decoding.kt.
 */

package kotlinx.serialization.encoding

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.modules.*

/**
 * Decoder is a core deserialization primitive that encapsulates the knowledge of the underlying
 * format and its storage, exposing only structural methods to the deserializer, making it
 * completely format-agnostic. Deserialization process transforms a single value into the
 * sequence of its primitive elements, also called its serial form, while decoding transforms
 * these primitive elements into an actual value.
 *
 * The symmetric interface for the serialization process is [Encoder].
 *
 * ### Not stable for inheritance
 *
 * `Decoder` interface is not stable for inheritance in 3rd party libraries, as new methods
 * might be added to this interface or contracts of the existing methods can be changed.
 */
public interface Decoder {
    /**
     * Context of the current decoding process, including contextual and polymorphic serialization and,
     * potentially, a format-specific configuration.
     */
    public val serializersModule: SerializersModule

    /**
     * Returns `true` if the current value in decoder is not null, `false` otherwise.
     * This method has a use in highly-performant binary formats and can
     * be safely ignored by most of the regular formats.
     */
    @ExperimentalSerializationApi
    public fun decodeNotNullMark(): Boolean

    /**
     * Decodes the `null` value.
     */
    @ExperimentalSerializationApi
    public fun decodeNull(): Nothing?

    /**
     * Decodes a boolean value.
     * Corresponding kind is [PrimitiveKind.BOOLEAN].
     */
    public fun decodeBoolean(): Boolean

    /**
     * Decodes a single byte value.
     * Corresponding kind is [PrimitiveKind.BYTE].
     */
    public fun decodeByte(): Byte

    /**
     * Decodes a 16-bit short value.
     * Corresponding kind is [PrimitiveKind.SHORT].
     */
    public fun decodeShort(): Short

    /**
     * Decodes a 16-bit unicode character value.
     * Corresponding kind is [PrimitiveKind.CHAR].
     */
    public fun decodeChar(): Char

    /**
     * Decodes a 32-bit integer value.
     * Corresponding kind is [PrimitiveKind.INT].
     */
    public fun decodeInt(): Int

    /**
     * Decodes a 64-bit integer value.
     * Corresponding kind is [PrimitiveKind.LONG].
     */
    public fun decodeLong(): Long

    /**
     * Decodes a 32-bit IEEE 754 floating point value.
     * Corresponding kind is [PrimitiveKind.FLOAT].
     */
    public fun decodeFloat(): Float

    /**
     * Decodes a 64-bit IEEE 754 floating point value.
     * Corresponding kind is [PrimitiveKind.DOUBLE].
     */
    public fun decodeDouble(): Double

    /**
     * Decodes a string value.
     * Corresponding kind is [PrimitiveKind.STRING].
     */
    public fun decodeString(): String

    /**
     * Decodes an index of enum element that is stored in [enumDescriptor] elements collection.
     * Corresponding kind is [SerialKind.ENUM].
     */
    public fun decodeEnum(enumDescriptor: SerialDescriptor): Int

    /**
     * Returns [Decoder] for decoding an underlying type of a value class in an inline manner.
     * Serializable value class is described by the given [descriptor].
     *
     * Calling [Decoder.beginStructure] on returned instance leads to an unspecified behavior and, in general,
     * is prohibited.
     */
    public fun decodeInline(descriptor: SerialDescriptor): Decoder

    /**
     * Decodes the beginning of the nested structure in a serialized form
     * and returns [CompositeDecoder] responsible for decoding this very structure.
     */
    public fun beginStructure(descriptor: SerialDescriptor): CompositeDecoder

    /**
     * Decodes the value of type [T] by delegating the decoding process to the given [deserializer].
     */
    public fun <T : Any?> decodeSerializableValue(deserializer: DeserializationStrategy<T>): T =
        deserializer.deserialize(this)

    /**
     * Decodes the nullable value of type [T] by delegating the decoding process to the given [deserializer].
     */
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

/**
 * [CompositeDecoder] is a part of decoding process that is bound to a particular structured part of
 * the serialized form, described by the serial descriptor passed to [Decoder.beginStructure].
 *
 * The symmetric interface for the serialization process is [CompositeEncoder].
 *
 * ### Not stable for inheritance
 *
 * `CompositeDecoder` interface is not stable for inheritance in 3rd party libraries, as new methods
 * might be added to this interface or contracts of the existing methods can be changed.
 */
public interface CompositeDecoder {

    /**
     * Results of [decodeElementIndex] used for decoding control flow.
     */
    public companion object {
        /**
         * Value of [decodeElementIndex] which means that the decoding process is finished
         * and all the elements have been successfully decoded.
         */
        public const val DECODE_DONE: Int = -1

        /**
         * Value of [decodeElementIndex] which means that the element was not found in the input,
         * or that the element is unknown.
         */
        public const val UNKNOWN_NAME: Int = -3
    }

    /**
     * Context of the current decoding process, including contextual and polymorphic serialization and,
     * potentially, a format-specific configuration.
     */
    public val serializersModule: SerializersModule

    /**
     * Denotes the end of the structure associated with current decoder.
     */
    public fun endStructure(descriptor: SerialDescriptor)

    /**
     * Returns `true` if the format can decode elements in a sequential order,
     * `false` if elements can be decoded only in a random order (e.g. by index).
     */
    @ExperimentalSerializationApi
    public fun decodeSequentially(): Boolean = false

    /**
     * Returns the index of the next element to be decoded or [DECODE_DONE] if there are no more elements.
     */
    public fun decodeElementIndex(descriptor: SerialDescriptor): Int

    /**
     * Returns the collection size that is being decoded.
     */
    public fun decodeCollectionSize(descriptor: SerialDescriptor): Int = -1

    /**
     * Decodes a boolean [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeBooleanElement(descriptor: SerialDescriptor, index: Int): Boolean

    /**
     * Decodes a single byte [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeByteElement(descriptor: SerialDescriptor, index: Int): Byte

    /**
     * Decodes a 16-bit unicode character [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeCharElement(descriptor: SerialDescriptor, index: Int): Char

    /**
     * Decodes a 16-bit short [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeShortElement(descriptor: SerialDescriptor, index: Int): Short

    /**
     * Decodes a 32-bit integer [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeIntElement(descriptor: SerialDescriptor, index: Int): Int

    /**
     * Decodes a 64-bit integer [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeLongElement(descriptor: SerialDescriptor, index: Int): Long

    /**
     * Decodes a 32-bit IEEE 754 floating point [value] associated with an element
     * at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeFloatElement(descriptor: SerialDescriptor, index: Int): Float

    /**
     * Decodes a 64-bit IEEE 754 floating point [value] associated with an element
     * at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeDoubleElement(descriptor: SerialDescriptor, index: Int): Double

    /**
     * Decodes a string [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun decodeStringElement(descriptor: SerialDescriptor, index: Int): String

    /**
     * Returns [Decoder] for decoding an underlying type of a value class in an inline manner.
     * Serializable value class is described by the [child descriptor][SerialDescriptor.getElementDescriptor]
     * of given [descriptor] at [index].
     *
     * Calling [Decoder.beginStructure] on returned instance leads to an unspecified behavior and, in general,
     * is prohibited.
     */
    public fun decodeInlineElement(
        descriptor: SerialDescriptor,
        index: Int
    ): Decoder

    /**
     * Delegates [value] decoding of the type [T] to the given [deserializer].
     * [value] is associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun <T : Any?> decodeSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        deserializer: DeserializationStrategy<T>,
        previousValue: T? = null
    ): T

    /**
     * Delegates nullable [value] decoding of the type [T] to the given [deserializer].
     * [value] is associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    @ExperimentalSerializationApi
    public fun <T : Any> decodeNullableSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        deserializer: DeserializationStrategy<T?>,
        previousValue: T? = null
    ): T?
}

/**
 * Begins a structure, decodes it using the given [block], ends it and returns decoded element.
 */
public inline fun <T> Decoder.decodeStructure(
    descriptor: SerialDescriptor,
    crossinline block: CompositeDecoder.() -> T
): T {
    val composite = beginStructure(descriptor)
    val result = composite.block()
    composite.endStructure(descriptor)
    return result
}
