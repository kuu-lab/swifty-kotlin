/*
 * Copyright 2017-2024 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization

import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** Describes and performs serialization for values of [T]. */
public interface KSerializer<T> {
    public val descriptor: SerialDescriptor

    public fun serialize(encoder: Encoder, value: T)

    public fun deserialize(decoder: Decoder): T
}
