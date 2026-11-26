/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/encoding/Encoding.kt.
 */

package kotlinx.serialization.encoding

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.modules.*

public interface Encoder {
    public val serializersModule: SerializersModule

    @ExperimentalSerializationApi
    public fun encodeNotNullMark() {}

    @ExperimentalSerializationApi
    public fun encodeNull()

    public fun encodeBoolean(value: Boolean)

    public fun encodeByte(value: Byte)

    public fun encodeShort(value: Short)

    public fun encodeChar(value: Char)

    public fun encodeInt(value: Int)

    public fun encodeLong(value: Long)

    public fun encodeFloat(value: Float)

    public fun encodeDouble(value: Double)

    public fun encodeString(value: String)

    public fun encodeEnum(enumDescriptor: SerialDescriptor, index: Int)

    public fun encodeInline(descriptor: SerialDescriptor): Encoder

    public fun beginStructure(descriptor: SerialDescriptor): CompositeEncoder

    public fun beginCollection(
        descriptor: SerialDescriptor,
        collectionSize: Int
    ): CompositeEncoder = beginStructure(descriptor)

    public fun <T : Any?> encodeSerializableValue(serializer: SerializationStrategy<T>, value: T) {
        serializer.serialize(this, value)
    }

    @Suppress("UNCHECKED_CAST")
    @ExperimentalSerializationApi
    public fun <T : Any> encodeNullableSerializableValue(serializer: SerializationStrategy<T>, value: T?) {
        val isNullabilitySupported = serializer.descriptor.isNullable
        if (isNullabilitySupported) {
            // Instead of `serializer.serialize` to be able to intercept this
            return encodeSerializableValue(serializer as SerializationStrategy<T?>, value)
        }

        if (value == null) {
            encodeNull()
        } else {
            encodeNotNullMark()
            encodeSerializableValue(serializer, value)
        }
    }
}

public interface CompositeEncoder {
    public val serializersModule: SerializersModule

    public fun endStructure(descriptor: SerialDescriptor)

    @ExperimentalSerializationApi
    public fun shouldEncodeElementDefault(descriptor: SerialDescriptor, index: Int): Boolean = true

    public fun encodeBooleanElement(descriptor: SerialDescriptor, index: Int, value: Boolean)

    public fun encodeByteElement(descriptor: SerialDescriptor, index: Int, value: Byte)

    public fun encodeShortElement(descriptor: SerialDescriptor, index: Int, value: Short)

    public fun encodeCharElement(descriptor: SerialDescriptor, index: Int, value: Char)

    public fun encodeIntElement(descriptor: SerialDescriptor, index: Int, value: Int)

    public fun encodeLongElement(descriptor: SerialDescriptor, index: Int, value: Long)

    public fun encodeFloatElement(descriptor: SerialDescriptor, index: Int, value: Float)

    public fun encodeDoubleElement(descriptor: SerialDescriptor, index: Int, value: Double)

    public fun encodeStringElement(descriptor: SerialDescriptor, index: Int, value: String)

    public fun encodeInlineElement(
        descriptor: SerialDescriptor,
        index: Int
    ): Encoder

    public fun <T : Any?> encodeSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        serializer: SerializationStrategy<T>,
        value: T
    )

    @ExperimentalSerializationApi
    public fun <T : Any> encodeNullableSerializableElement(
        descriptor: SerialDescriptor,
        index: Int,
        serializer: SerializationStrategy<T>,
        value: T?
    )
}

public inline fun Encoder.encodeStructure(
    descriptor: SerialDescriptor,
    crossinline block: CompositeEncoder.() -> Unit
) {
    val composite = beginStructure(descriptor)
    composite.block()
    composite.endStructure(descriptor)
}

public inline fun Encoder.encodeCollection(
    descriptor: SerialDescriptor,
    collectionSize: Int,
    crossinline block: CompositeEncoder.() -> Unit
) {
    val composite = beginCollection(descriptor, collectionSize)
    composite.block()
    composite.endStructure(descriptor)
}

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
