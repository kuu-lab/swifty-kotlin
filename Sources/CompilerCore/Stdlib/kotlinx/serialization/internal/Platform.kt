/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/internal/Platform.common.kt.
 * Only the parts that do not require the serialization compiler plugin are ported; the upstream
 * `expect` hooks for compiled/builtin serializer lookup do not exist in this toolchain.
 */
@file:OptIn(ExperimentalSerializationApi::class)
package kotlinx.serialization.internal

import kotlinx.serialization.*
import kotlin.reflect.*

@Suppress("UNCHECKED_CAST", "NOTHING_TO_INLINE")
@PublishedApi
internal inline fun <T> KSerializer<*>.cast(): KSerializer<T> = this as KSerializer<T>

@Suppress("UNCHECKED_CAST", "NOTHING_TO_INLINE")
@PublishedApi
internal inline fun <T> SerializationStrategy<*>.cast(): SerializationStrategy<T> = this as SerializationStrategy<T>

@Suppress("UNCHECKED_CAST", "NOTHING_TO_INLINE")
@PublishedApi
internal inline fun <T> DeserializationStrategy<*>.cast(): DeserializationStrategy<T> =
    this as DeserializationStrategy<T>

internal fun KClass<*>.serializerNotRegistered(): Nothing {
    throw SerializationException(notRegisteredMessage())
}

internal fun KClass<*>.notRegisteredMessage(): String = notRegisteredMessage(simpleName ?: "<local class name not available>")

internal fun notRegisteredMessage(className: String): String = "Serializer for class '$className' is not found.\n" +
        "Please ensure that class is marked as '@Serializable' and that the serialization compiler plugin is applied.\n"

@Suppress("UNCHECKED_CAST")
internal fun KType.kclass() = when (val t = classifier) {
    is KClass<*> -> t
    is KTypeParameter -> {
        throw IllegalArgumentException(
            "Captured type parameter $t from generic non-reified function. " +
                    "Such functionality cannot be supported because $t is erased, either specify serializer explicitly or make " +
                    "calling function inline with reified $t."
        )
    }

    else ->  throw IllegalArgumentException("Only KClass supported as classifier, got $t")
} as KClass<Any>

internal fun KTypeProjection.typeOrThrow(): KType = requireNotNull(type) { "Star projections in type arguments are not allowed, but had $type" }
