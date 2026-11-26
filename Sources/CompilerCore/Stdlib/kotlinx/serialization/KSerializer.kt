/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/KSerializer.kt.
 */

package kotlinx.serialization

import kotlinx.serialization.descriptors.*
import kotlinx.serialization.encoding.*

public interface KSerializer<T> : SerializationStrategy<T>, DeserializationStrategy<T> {
    override val descriptor: SerialDescriptor
}

public interface SerializationStrategy<in T> {
    public val descriptor: SerialDescriptor

    public fun serialize(encoder: Encoder, value: T)
}

public interface DeserializationStrategy<out T> {
    public val descriptor: SerialDescriptor

    public fun deserialize(decoder: Decoder): T
}
