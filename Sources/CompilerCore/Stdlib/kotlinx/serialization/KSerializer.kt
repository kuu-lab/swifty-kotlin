/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/KSerializer.kt.
 */

package kotlinx.serialization

import kotlinx.serialization.descriptors.*
import kotlinx.serialization.encoding.*

/**
 * KSerializer is responsible for the representation of a serial form of a type [T]
 * in terms of [encoders][Encoder] and [decoders][Decoder] and for constructing and deconstructing [T]
 * from/to a sequence of encoding primitives.
 *
 * Implementations of [serialize] and [deserialize] methods are allowed to throw
 * any subtype of [IllegalArgumentException] in order to indicate serialization
 * and deserialization errors.
 */
public interface KSerializer<T> : SerializationStrategy<T>, DeserializationStrategy<T> {
    /**
     * Describes the structure of the serializable representation of [T], produced
     * by this serializer.
     */
    override val descriptor: SerialDescriptor
}

/**
 * Serialization strategy defines the serial form of a type [T], including its structural description,
 * declared by the [descriptor] and the actual serialization process, defined by the implementation
 * of the [serialize] method.
 *
 * @throws SerializationException in case of any serialization-specific error
 * @throws IllegalArgumentException if the supplied input does not comply encoder's specification
 */
public interface SerializationStrategy<in T> {
    /**
     * Describes the structure of the serializable representation of [T], produced
     * by this serializer.
     */
    public val descriptor: SerialDescriptor

    /**
     * Serializes the [value] of type [T] using the format that is represented by the given [encoder].
     * [serialize] method is format-agnostic and operates with a high-level structured [Encoder] API.
     * Throws [SerializationException] if value cannot be serialized.
     */
    public fun serialize(encoder: Encoder, value: T)
}

/**
 * Deserialization strategy defines the serial form of a type [T], including its structural description,
 * declared by the [descriptor] and the actual deserialization process, defined by the implementation
 * of the [deserialize] method.
 *
 * @throws MissingFieldException if non-optional fields were not found during deserialization
 * @throws SerializationException in case of any deserialization-specific error
 * @throws IllegalArgumentException if the decoded input is not a valid instance of [T]
 */
public interface DeserializationStrategy<out T> {
    /**
     * Describes the structure of the serializable representation of [T], that current
     * deserializer is able to deserialize.
     */
    public val descriptor: SerialDescriptor

    /**
     * Deserializes the value of type [T] using the format that is represented by the given [decoder].
     * [deserialize] method is format-agnostic and operates with a high-level structured [Decoder] API.
     * Throws [SerializationException] if value cannot be deserialized.
     */
    public fun deserialize(decoder: Decoder): T
}
