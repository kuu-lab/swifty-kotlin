/*
 * Copyright 2017-2024 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization.builtins

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.nullable
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** Returns a serializer that also accepts and emits null values. */
public val <T : Any> KSerializer<T>.nullable: KSerializer<T?>
    get() = NullableSerializer(this)

private class NullableSerializer<T : Any>(
    private val serializer: KSerializer<T>
) : KSerializer<T?> {
    override val descriptor: SerialDescriptor
        get() = serializer.descriptor.nullable

    override fun serialize(encoder: Encoder, value: T?) {
        if (value == null) {
            encoder.encodeNull()
        } else {
            encoder.encodeNotNullMark()
            serializer.serialize(encoder, value)
        }
    }

    override fun deserialize(decoder: Decoder): T? =
        if (decoder.decodeNotNullMark()) serializer.deserialize(decoder) else decoder.decodeNull()
}
