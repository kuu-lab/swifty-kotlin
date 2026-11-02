/*
 * Copyright 2017-2024 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization

import kotlin.reflect.KClass
import kotlin.reflect.KType
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.modules.SerializersModule

/** Returns the serializer generated for [T] by the serialization compiler plugin. */
public inline fun <reified T> serializer(): KSerializer<T> =
    error("Serializer lookup is unavailable because the serialization compiler plugin is not implemented")

/** Resolves a serializer from a reflected type. */
@InternalSerializationApi
public fun serializer(type: KType): KSerializer<Any?> = UnavailableSerializer()

/** Resolves a serializer from a reflected class. */
@InternalSerializationApi
public fun KClass<*>.serializer(): KSerializer<Any?> = UnavailableSerializer()

/** Resolves a serializer using this module and reflected type. */
@OptIn(InternalSerializationApi::class)
@InternalSerializationApi
public fun SerializersModule.serializer(type: KType): KSerializer<Any?> =
    kotlinx.serialization.serializer(type)

private class UnavailableSerializer<T> : KSerializer<T> {
    override val descriptor: SerialDescriptor
        get() = unavailable()

    override fun serialize(encoder: Encoder, value: T): Unit = unavailable()

    override fun deserialize(decoder: Decoder): T = unavailable()

    private fun unavailable(): Nothing =
        error("Serializer lookup is unavailable because the serialization compiler plugin is not implemented")
}
