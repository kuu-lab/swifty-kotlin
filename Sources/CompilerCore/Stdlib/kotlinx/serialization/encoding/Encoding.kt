/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/encoding/Encoding.kt.
 */

package kotlinx.serialization.encoding

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.modules.*

/**
 * Encoder is a core serialization primitive that encapsulates the knowledge of the underlying
 * format and its storage, exposing only structural methods to the serializer, making it completely
 * format-agnostic. Serialization process transforms a single value into the sequence of its
 * primitive elements, also called its serial form, while encoding transforms these primitive
 * elements into an actual format representation: JSON string, ProtoBuf ByteArray,
 * in-memory map representation etc.
 *
 * The symmetric interface for the deserialization process is [Decoder].
 *
 * ### Not stable for inheritance
 *
 * `Encoder` interface is not stable for inheritance in 3rd party libraries, as new methods
 * might be added to this interface or contracts of the existing methods can be changed.
 */
public interface Encoder {
    /**
     * Context of the current serialization process, including contextual and polymorphic serialization and,
     * potentially, a format-specific configuration.
     */
    public val serializersModule: SerializersModule

    /**
     * Notifies the encoder that value of a nullable type that is
     * being serialized is not null. It should be called before writing a non-null value
     * of nullable type.
     *
     * This method has a use in highly-performant binary formats and can
     * be safely ignored by most of the regular formats.
     */
    @ExperimentalSerializationApi
    public fun encodeNotNullMark() {}

    /**
     * Encodes `null` value.
     */
    @ExperimentalSerializationApi
    public fun encodeNull()

    /**
     * Encodes a boolean value.
     * Corresponding kind is [PrimitiveKind.BOOLEAN].
     */
    public fun encodeBoolean(value: Boolean)

    /**
     * Encodes a single byte value.
     * Corresponding kind is [PrimitiveKind.BYTE].
     */
    public fun encodeByte(value: Byte)

    /**
     * Encodes a 16-bit short value.
     * Corresponding kind is [PrimitiveKind.SHORT].
     */
    public fun encodeShort(value: Short)

    /**
     * Encodes a 16-bit unicode character value.
     * Corresponding kind is [PrimitiveKind.CHAR].
     */
    public fun encodeChar(value: Char)

    /**
     * Encodes a 32-bit integer value.
     * Corresponding kind is [PrimitiveKind.INT].
     */
    public fun encodeInt(value: Int)

    /**
     * Encodes a 64-bit integer value.
     * Corresponding kind is [PrimitiveKind.LONG].
     */
    public fun encodeLong(value: Long)

    /**
     * Encodes a 32-bit IEEE 754 floating point value.
     * Corresponding kind is [PrimitiveKind.FLOAT].
     */
    public fun encodeFloat(value: Float)

    /**
     * Encodes a 64-bit IEEE 754 floating point value.
     * Corresponding kind is [PrimitiveKind.DOUBLE].
     */
    public fun encodeDouble(value: Double)

    /**
     * Encodes a string value.
     * Corresponding kind is [PrimitiveKind.STRING].
     */
    public fun encodeString(value: String)

    /**
     * Encodes an enum value that is stored at the [index] in [enumDescriptor] elements collection.
     * Corresponding kind is [SerialKind.ENUM].
     */
    public fun encodeEnum(enumDescriptor: SerialDescriptor, index: Int)

    /**
     * Returns [Encoder] for encoding an underlying type of a value class in an inline manner.
     * [descriptor] describes a serializable value class.
     *
     * Calling [Encoder.beginStructure] on returned instance leads to an unspecified behavior and, in general,
     * is prohibited.
     */
    public fun encodeInline(descriptor: SerialDescriptor): Encoder

    /**
     * Encodes the beginning of the nested structure in a serialized form
     * and returns [CompositeEncoder] responsible for encoding this very structure.
     */
    public fun beginStructure(descriptor: SerialDescriptor): CompositeEncoder

    /**
     * Encodes the beginning of the collection with size [collectionSize] and the given serializer of its type parameters.
     * This method has to be implemented only if you need to know collection size in advance,
     * otherwise, [beginStructure] can be used.
     */
    public fun beginCollection(
        descriptor: SerialDescriptor,
        collectionSize: Int
    ): CompositeEncoder = beginStructure(descriptor)

    /**
     * Encodes the [value] of type [T] by delegating the encoding process to the given [serializer].
     */
    public fun <T : Any?> encodeSerializableValue(serializer: SerializationStrategy<T>, value: T) {
        serializer.serialize(this, value)
    }

    /**
     * Encodes the nullable [value] of type [T] by delegating the encoding process to the given [serializer].
     */
    @Suppress("UNCHECKED_CAST")
    @ExperimentalSerializationApi
    public fun <T : Any> encodeNullableSerializableValue(serializer: SerializationStrategy<T>, value: T?) {
        val isNullabilitySupported = serializer.descriptor.isNullable
        if (isNullabilitySupported) {
            // Instead of `serializer.serialize` to be able to intercept this
            return encodeSerializableValue(serializer as SerializationStrategy<T?>, value)
        }

        // Else default path used to avoid allocation of NullableSerializer
        if (value == null) {
            encodeNull()
        } else {
            encodeNotNullMark()
            encodeSerializableValue(serializer, value)
        }
    }
}

/**
 * [CompositeEncoder] is a part of encoding process that is bound to a particular structured part of
 * the serialized form, described by the serial descriptor passed to [Encoder.beginStructure].
 *
 * The symmetric interface for the deserialization process is [CompositeDecoder].
 *
 * ### Not stable for inheritance
 *
 * `CompositeEncoder` interface is not stable for inheritance in 3rd party libraries, as new methods
 * might be added to this interface or contracts of the existing methods can be changed.
 */
public interface CompositeEncoder {
    /**
     * Context of the current serialization process, including contextual and polymorphic serialization and,
     * potentially, a format-specific configuration.
     */
    public val serializersModule: SerializersModule

    /**
     * Denotes the end of the structure associated with current encoder.
     */
    public fun endStructure(descriptor: SerialDescriptor)

    /**
     * Whether the format should encode values that are equal to the default values.
     * This method is used by plugin-generated serializers for properties with default values.
     *
     * This method is never invoked for properties annotated with [EncodeDefault].
     */
    @ExperimentalSerializationApi
    public fun shouldEncodeElementDefault(descriptor: SerialDescriptor, index: Int): Boolean = true

    /**
     * Encodes a boolean [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.BOOLEAN] kind.
     */
    public fun encodeBooleanElement(descriptor: SerialDescriptor, index: Int, value: Boolean)

    /**
     * Encodes a single byte [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.BYTE] kind.
     */
    public fun encodeByteElement(descriptor: SerialDescriptor, index: Int, value: Byte)

    /**
     * Encodes a 16-bit short [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.SHORT] kind.
     */
    public fun encodeShortElement(descriptor: SerialDescriptor, index: Int, value: Short)

    /**
     * Encodes a 16-bit unicode character [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.CHAR] kind.
     */
    public fun encodeCharElement(descriptor: SerialDescriptor, index: Int, value: Char)

    /**
     * Encodes a 32-bit integer [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.INT] kind.
     */
    public fun encodeIntElement(descriptor: SerialDescriptor, index: Int, value: Int)

    /**
     * Encodes a 64-bit integer [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.LONG] kind.
     */
    public fun encodeLongElement(descriptor: SerialDescriptor, index: Int, value: Long)

    /**
     * Encodes a 32-bit IEEE 754 floating point [value] associated with an element
     * at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.FLOAT] kind.
     */
    public fun encodeFloatElement(descriptor: SerialDescriptor, index: Int, value: Float)

    /**
     * Encodes a 64-bit IEEE 754 floating point [value] associated with an element
     * at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.DOUBLE] kind.
     */
    public fun encodeDoubleElement(descriptor: SerialDescriptor, index: Int, value: Double)

    /**
     * Encodes a string [value] associated with an element at the given [index] in [serial descriptor][descriptor].
     * The element at the given [index] should have [PrimitiveKind.STRING] kind.
     */
    public fun encodeStringElement(descriptor: SerialDescriptor, index: Int, value: String)

    /**
     * Returns [Encoder] for encoding an underlying type of a value class in an inline manner.
     * Serializable value class is described by the [child descriptor][SerialDescriptor.getElementDescriptor]
     * of given [descriptor] at [index].
     *
     * Calling [Encoder.beginStructure] on returned instance leads to an unspecified behavior and, in general,
     * is prohibited.
     */
    public fun encodeInlineElement(
        descriptor: SerialDescriptor,
        index: Int
    ): Encoder

    /**
     * Delegates [value] encoding of the type [T] to the given [serializer].
     * [value] is associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    public fun <T : Any?> encodeSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        serializer: SerializationStrategy<T>,
        value: T
    )

    /**
     * Delegates nullable [value] encoding of the type [T] to the given [serializer].
     * [value] is associated with an element at the given [index] in [serial descriptor][descriptor].
     */
    @ExperimentalSerializationApi
    public fun <T : Any> encodeNullableSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        serializer: SerializationStrategy<T>,
        value: T?
    )
}

/**
 * Begins a structure, encodes it using the given [block] and ends it.
 */
public inline fun Encoder.encodeStructure(
    descriptor: SerialDescriptor,
    crossinline block: CompositeEncoder.() -> Unit
) {
    val composite = beginStructure(descriptor)
    composite.block()
    composite.endStructure(descriptor)
}

/**
 * Begins a collection, encodes it using the given [block] and ends it.
 */
public inline fun Encoder.encodeCollection(
    descriptor: SerialDescriptor,
    collectionSize: Int,
    crossinline block: CompositeEncoder.() -> Unit
) {
    val composite = beginCollection(descriptor, collectionSize)
    composite.block()
    composite.endStructure(descriptor)
}

/**
 * Begins a collection, calls [block] with each item and ends the collections.
 */
public inline fun <E> Encoder.encodeCollection(
    descriptor: SerialDescriptor,
    collection: Collection<E>,
    crossinline block: CompositeEncoder.(index: Int, E) -> Unit
) {
    encodeCollection(descriptor, collection.size) {
        collection.forEachIndexed { index, e ->
            block(index, e)
        }
    }
}
