/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/internal/NullableSerializer.kt.
 * `SerialDescriptorForNullable` lives in its own file in this tree.
 */
@file:OptIn(ExperimentalSerializationApi::class)
package kotlinx.serialization.internal

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.*
import kotlinx.serialization.encoding.*

/**
 * Use [KSerializer.nullable][kotlinx.serialization.builtins.nullable] instead.
 * @suppress internal API
 */
@PublishedApi
internal class NullableSerializer<T : Any>(private val serializer: KSerializer<T>) : KSerializer<T?> {
    override val descriptor: SerialDescriptor = SerialDescriptorForNullable(serializer.descriptor)

    override fun serialize(encoder: Encoder, value: T?) {
        if (value != null) {
            encoder.encodeNotNullMark()
            encoder.encodeSerializableValue(serializer, value)
        } else {
            encoder.encodeNull()
        }
    }

    override fun deserialize(decoder: Decoder): T? {
        return if (decoder.decodeNotNullMark()) decoder.decodeSerializableValue(serializer) else decoder.decodeNull()
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false
        other as NullableSerializer<*>
        if (serializer != other.serializer) return false
        return true
    }

    override fun hashCode(): Int {
        return serializer.hashCode()
    }
}
