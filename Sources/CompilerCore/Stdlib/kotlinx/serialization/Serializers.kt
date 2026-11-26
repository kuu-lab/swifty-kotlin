/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/Serializers.kt.
 * Generated companion entry points are installed by the compiler plugin. The shared
 * serializer lookup also supports primitive serializers and reflective serializers for
 * classes carrying the bundled [Serializable] annotation.
 */
@file:Suppress("DEPRECATION_ERROR", "UNCHECKED_CAST")
@file:OptIn(InternalSerializationApi::class)

package kotlinx.serialization

import kotlinx.serialization.builtins.*
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.internal.*
import kotlinx.serialization.modules.*
import kotlin.reflect.*

public inline fun <reified T> serializer(): KSerializer<T> {
    return serializer(typeOf<T>()).cast()
}

public inline fun <reified T> SerializersModule.serializer(): KSerializer<T> {
    return serializer(typeOf<T>()).cast()
}

public fun serializer(type: KType): KSerializer<Any?> = EmptySerializersModule().serializer(type)


@ExperimentalSerializationApi
public fun serializer(
    kClass: KClass<*>,
    typeArgumentsSerializers: List<KSerializer<*>>,
    isNullable: Boolean
): KSerializer<Any?> = EmptySerializersModule().serializer(kClass, typeArgumentsSerializers, isNullable)

public fun serializerOrNull(type: KType): KSerializer<Any?>? = EmptySerializersModule().serializerOrNull(type)

public fun SerializersModule.serializer(type: KType): KSerializer<Any?> =
    serializerByKTypeImpl(type, failOnMissingTypeArgSerializer = true) ?: type.kclass()
        .serializerNotRegistered()


@ExperimentalSerializationApi
public fun SerializersModule.serializer(
    kClass: KClass<*>,
    typeArgumentsSerializers: List<KSerializer<*>>,
    isNullable: Boolean
): KSerializer<Any?> =
    serializerByKClassImpl(kClass as KClass<Any>, typeArgumentsSerializers as List<KSerializer<Any?>>, isNullable)
        ?: kClass.serializerNotRegistered()

public fun SerializersModule.serializerOrNull(type: KType): KSerializer<Any?>? =
    serializerByKTypeImpl(type, failOnMissingTypeArgSerializer = false)

@OptIn(ExperimentalSerializationApi::class)
private fun SerializersModule.serializerByKTypeImpl(
    type: KType,
    failOnMissingTypeArgSerializer: Boolean
): KSerializer<Any?>? {
    val rootClass = type.kclass()
    val isNullable = type.isMarkedNullable
    val typeArguments = type.arguments.map { it.typeOrThrow() }

    val defaultSerializer = rootClass.serializerOrNull()
    val contextualSerializer: KSerializer<out Any?>? = if (typeArguments.isEmpty()) {
        getContextual(rootClass)
    } else {
        val serializers = serializersForParameters(typeArguments, failOnMissingTypeArgSerializer) ?: return null
        getContextual(rootClass, serializers)
    }
    return (contextualSerializer ?: defaultSerializer)?.cast<Any>()?.nullable(isNullable)
}

@OptIn(ExperimentalSerializationApi::class)
private fun SerializersModule.serializerByKClassImpl(
    rootClass: KClass<Any>,
    typeArgumentsSerializers: List<KSerializer<Any?>>,
    isNullable: Boolean
): KSerializer<Any?>? {
    val serializer = getContextual(rootClass, typeArgumentsSerializers) ?: rootClass.serializerOrNull()
    return serializer?.cast<Any>()?.nullable(isNullable)
}

internal fun SerializersModule.serializersForParameters(
    typeArguments: List<KType>,
    failOnMissingTypeArgSerializer: Boolean
): List<KSerializer<Any?>>? {
    val serializers = if (failOnMissingTypeArgSerializer) {
        typeArguments.map { serializer(it) }
    } else {
        typeArguments.map { serializerOrNull(it) ?: return null }
    }
    return serializers
}

@InternalSerializationApi
public fun <T : Any> KClass<T>.serializer(): KSerializer<T> = serializerOrNull() ?: serializerNotRegistered()

@InternalSerializationApi
public fun <T : Any> KClass<T>.serializerOrNull(): KSerializer<T>? =
    builtinSerializerOrNull(this) ?: if (annotations.any { it is Serializable }) {
        ReflectiveClassSerializer(this)
    } else {
        null
    }

private fun <T : Any> KSerializer<T>.nullable(shouldBeNullable: Boolean): KSerializer<T?> {
    if (shouldBeNullable) return this.nullable
    return this as KSerializer<T?>
}
