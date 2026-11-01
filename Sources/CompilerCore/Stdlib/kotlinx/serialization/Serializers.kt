/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/Serializers.kt.
 * The public `serializer*` entry points keep their upstream signatures, but the lookup is
 * reduced to the contextual [SerializersModule] path: plugin-generated serializers,
 * platform reflection and the builtin serializer registry do not exist in this toolchain,
 * so unresolved lookups fail with [SerializationException] instead of consulting them.
 */
@file:Suppress("DEPRECATION_ERROR", "UNCHECKED_CAST")

package kotlinx.serialization

import kotlinx.serialization.builtins.*
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.internal.*
import kotlinx.serialization.modules.*
import kotlin.reflect.*

/**
 * Retrieves a serializer for the given type [T].
 * This overload is a reified version of `serializer(KType)`.
 *
 * @throws SerializationException if serializer cannot be created (provided [T] or its type argument is not serializable).
 * @throws IllegalArgumentException if any of [T]'s type arguments contains star projection
 */
public inline fun <reified T> serializer(): KSerializer<T> {
    return serializer(typeOf<T>()).cast()
}

/**
 * Retrieves default serializer for the given type [T] and,
 * if [T] is not serializable, fallbacks to [contextual][SerializersModule.getContextual] lookup.
 *
 * @throws SerializationException if serializer cannot be created (provided [T] or its type argument is not serializable).
 * @throws IllegalArgumentException if any of [T]'s type arguments contains star projection
 */
public inline fun <reified T> SerializersModule.serializer(): KSerializer<T> {
    return serializer(typeOf<T>()).cast()
}

/**
 * Creates a serializer for the given [type].
 * [type] argument is usually obtained with [typeOf] method.
 *
 * **Pitfall**: the returned serializer may return incorrect results or throw a [ClassCastException] if it receives
 * a value that's not a valid instance of the [KType], even though the type allows passing such a value.
 * Consider using the `serializer()` overload accepting a type argument (for example, `serializer<List<String>>()`),
 * which returns the serializer with the correct type.
 *
 * @throws SerializationException if serializer cannot be created (provided [type] or its type argument is not serializable).
 * @throws IllegalArgumentException if any of [type]'s arguments contains star projection
 */
public fun serializer(type: KType): KSerializer<Any?> = EmptySerializersModule().serializer(type)


/**
 * Retrieves serializer for the given [kClass].
 * This method uses platform-specific reflection available.
 *
 * If [kClass] is a parametrized type then it is necessary to pass serializers for generic parameters in the [typeArgumentsSerializers].
 * The nullability of returned serializer is specified using the [isNullable].
 *
 * @throws SerializationException if serializer cannot be created (provided [kClass] or its type argument is not serializable)
 * @throws SerializationException if [kClass] is a `kotlin.Array`
 * @throws SerializationException if size of [typeArgumentsSerializers] does not match the expected generic parameters count
 */
@ExperimentalSerializationApi
public fun serializer(
    kClass: KClass<*>,
    typeArgumentsSerializers: List<KSerializer<*>>,
    isNullable: Boolean
): KSerializer<Any?> = EmptySerializersModule().serializer(kClass, typeArgumentsSerializers, isNullable)

/**
 * Creates a serializer for the given [type] if possible.
 * [type] argument is usually obtained with [typeOf] method.
 *
 * @return [KSerializer] for the given [type] or `null` if serializer cannot be created (given [type] or its type argument is not serializable).
 * @throws IllegalArgumentException if any of [type]'s arguments contains star projection
 */
public fun serializerOrNull(type: KType): KSerializer<Any?>? = EmptySerializersModule().serializerOrNull(type)

/**
 * Retrieves default serializer for the given [type] and,
 * if [type] is not serializable, fallbacks to [contextual][SerializersModule.getContextual] lookup.
 * [type] argument is usually obtained with [typeOf] method.
 *
 * @throws SerializationException if serializer cannot be created (provided [type] or its type argument is not serializable and is not registered in [this] module).
 * @throws IllegalArgumentException if any of [type]'s arguments contains star projection
 */
public fun SerializersModule.serializer(type: KType): KSerializer<Any?> =
    serializerByKTypeImpl(type, failOnMissingTypeArgSerializer = true) ?: type.kclass()
        .serializerNotRegistered()


/**
 * Retrieves serializer for the given [kClass] and,
 * if [kClass] is not serializable, fallbacks to [contextual][SerializersModule.getContextual] lookup.
 * This method uses platform-specific reflection available.
 *
 * If [kClass] is a parametrized type then it is necessary to pass serializers for generic parameters in the [typeArgumentsSerializers].
 * The nullability of returned serializer is specified using the [isNullable].
 *
 * @throws SerializationException if serializer cannot be created (provided [kClass] or its type argument is not serializable and is not registered in [this] module)
 * @throws SerializationException if [kClass] is a `kotlin.Array`
 * @throws SerializationException if size of [typeArgumentsSerializers] does not match the expected generic parameters count
 */
@ExperimentalSerializationApi
public fun SerializersModule.serializer(
    kClass: KClass<*>,
    typeArgumentsSerializers: List<KSerializer<*>>,
    isNullable: Boolean
): KSerializer<Any?> =
    serializerByKClassImpl(kClass as KClass<Any>, typeArgumentsSerializers as List<KSerializer<Any?>>, isNullable)
        ?: kClass.serializerNotRegistered()

/**
 * Retrieves default serializer for the given [type] and,
 * if [type] is not serializable, fallbacks to [contextual][SerializersModule.getContextual] lookup.
 * [type] argument is usually obtained with [typeOf] method.
 *
 * @return [KSerializer] for the given [type] or `null` if serializer cannot be created (given [type] or its type argument is not serializable and is not registered in [this] module).
 * @throws IllegalArgumentException if any of [type]'s arguments contains star projection
 */
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

    // Unlike upstream there is no plugin-generated serializer lookup or builtin registry:
    // only contextual serializers registered in this module can be resolved.
    val contextualSerializer: KSerializer<out Any?>? = if (typeArguments.isEmpty()) {
        getContextual(rootClass)
    } else {
        val serializers = serializersForParameters(typeArguments, failOnMissingTypeArgSerializer) ?: return null
        getContextual(rootClass, serializers)
    }
    return contextualSerializer?.cast<Any>()?.nullable(isNullable)
}

@OptIn(ExperimentalSerializationApi::class)
private fun SerializersModule.serializerByKClassImpl(
    rootClass: KClass<Any>,
    typeArgumentsSerializers: List<KSerializer<Any?>>,
    isNullable: Boolean
): KSerializer<Any?>? {
    val serializer = getContextual(rootClass, typeArgumentsSerializers)
    return serializer?.cast<Any>()?.nullable(isNullable)
}

/**
 * Returns null only if `failOnMissingTypeArgSerializer == false` and at least one parameter serializer not found.
 */
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

/**
 * Retrieves a [KSerializer] for the given [KClass].
 * The given class must be annotated with [Serializable] or be one of the built-in types.
 *
 * This toolchain has no serialization compiler plugin, so only classes resolvable through
 * platform-independent means can return a serializer; every other class reports
 * [SerializationException] via [serializerNotRegistered].
 */
@InternalSerializationApi
public fun <T : Any> KClass<T>.serializer(): KSerializer<T> = serializerOrNull() ?: serializerNotRegistered()

/**
 * Retrieves a [KSerializer] for the given [KClass] or returns `null` if none is found.
 * The given class must be annotated with [Serializable] or be one of the built-in types.
 */
@InternalSerializationApi
public fun <T : Any> KClass<T>.serializerOrNull(): KSerializer<T>? = null

private fun <T : Any> KSerializer<T>.nullable(shouldBeNullable: Boolean): KSerializer<T?> {
    if (shouldBeNullable) return this.nullable
    return this as KSerializer<T?>
}
