/*
 * Copyright 2017-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization.json

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerializationException
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.StringFormat
import kotlinx.serialization.serializer
import kotlinx.serialization.modules.EmptySerializersModule
import kotlinx.serialization.modules.SerializersModule

/**
 * Entry point for JSON serialization.
 *
 * This bundled compatibility surface does not include the kotlinx.serialization compiler plugin
 * or a JSON encoder/decoder. Calls to encode or decode therefore fail explicitly at runtime.
 */
public abstract class Json : StringFormat {
    public override val serializersModule: SerializersModule
        get() = EmptySerializersModule()

    /** Encodes [value] using the supplied [serializer]. */
    @Suppress("UNUSED_PARAMETER")
    public override fun <T> encodeToString(serializer: SerializationStrategy<T>, value: T): String =
        unsupportedJsonOperation()

    /** Encodes [value] using its generated or registered serializer. */
    public inline fun <reified T> encodeToString(value: T): String =
        encodeToString(serializer<T>(), value)

    /** Decodes [string] using the supplied [deserializer]. */
    @Suppress("UNUSED_PARAMETER")
    public override fun <T> decodeFromString(deserializer: DeserializationStrategy<T>, string: String): T =
        unsupportedJsonOperation()

    /** Decodes [string] using the generated or registered deserializer. */
    public inline fun <reified T> decodeFromString(string: String): T =
        decodeFromString(serializer<T>(), string)

    public companion object Default : Json()
}

private fun <T> unsupportedJsonOperation(): T = throw SerializationException(
    "JSON encoding and decoding are unavailable in the bundled kotlinx.serialization compatibility API"
)
