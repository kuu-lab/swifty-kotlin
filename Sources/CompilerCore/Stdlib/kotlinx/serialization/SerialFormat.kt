/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization

import kotlinx.serialization.modules.SerializersModule

public interface SerialFormat {
    public val serializersModule: SerializersModule
}

public interface StringFormat : SerialFormat {
    public fun <T> encodeToString(serializer: SerializationStrategy<T>, value: T): String

    public fun <T> decodeFromString(deserializer: DeserializationStrategy<T>, string: String): T
}

public inline fun <reified T> StringFormat.encodeToString(value: T): String =
    encodeToString(serializer<T>(), value)

public inline fun <reified T> StringFormat.decodeFromString(string: String): T =
    decodeFromString(serializer<T>(), string)
