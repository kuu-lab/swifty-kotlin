/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/modules/SerializersModuleBuilders.kt.
 */

package kotlinx.serialization.modules

import kotlinx.serialization.*
import kotlinx.serialization.internal.*
import kotlin.reflect.*

public fun <T : Any> serializersModuleOf(kClass: KClass<T>, serializer: KSerializer<T>): SerializersModule =
    SerializersModule { contextual(kClass, serializer) }

public inline fun <reified T : Any> serializersModuleOf(serializer: KSerializer<T>): SerializersModule =
    serializersModuleOf(T::class, serializer)

@Suppress("FunctionName")
public inline fun SerializersModule(builderAction: SerializersModuleBuilder.() -> Unit): SerializersModule {
    val builder = SerializersModuleBuilder()
    builder.builderAction()
    return builder.build()
}

@Suppress("FunctionName")
public fun EmptySerializersModule(): SerializersModule = @Suppress("DEPRECATION") EmptySerializersModule

@OptIn(ExperimentalSerializationApi::class)
public class SerializersModuleBuilder @PublishedApi internal constructor() : SerializersModuleCollector {
    private val class2ContextualProvider: MutableMap<KClass<*>, ContextualProvider> = hashMapOf()
    private val polyBase2Serializers: MutableMap<KClass<*>, MutableMap<KClass<*>, KSerializer<*>>> = hashMapOf()
    private val polyBase2DefaultSerializerProvider: MutableMap<KClass<*>, PolymorphicSerializerProvider<*>> = hashMapOf()
    private val polyBase2NamedSerializers: MutableMap<KClass<*>, MutableMap<String, KSerializer<*>>> = hashMapOf()
    private val polyBase2DefaultDeserializerProvider: MutableMap<KClass<*>, PolymorphicDeserializerProvider<*>> = hashMapOf()
    private var hasInterfaceContextualSerializers: Boolean = false

    public override fun <T : Any> contextual(kClass: KClass<T>, serializer: KSerializer<T>): Unit =
        registerSerializer(kClass, ContextualProvider.Argless(serializer))

    public override fun <T : Any> contextual(
        kClass: KClass<T>,
        provider: (typeArgumentsSerializers: List<KSerializer<*>>) -> KSerializer<*>
    ): Unit = registerSerializer(kClass, ContextualProvider.WithTypeArguments(provider))

    public override fun <Base : Any, Sub : Base> polymorphic(
        baseClass: KClass<Base>,
        actualClass: KClass<Sub>,
        actualSerializer: KSerializer<Sub>
    ) {
        registerPolymorphicSerializer(baseClass, actualClass, actualSerializer)
    }

    public override fun <Base : Any> polymorphicDefaultSerializer(
        baseClass: KClass<Base>,
        defaultSerializerProvider: (value: Base) -> SerializationStrategy<Base>?
    ) {
        registerDefaultPolymorphicSerializer(baseClass, defaultSerializerProvider, false)
    }

    public override fun <Base : Any> polymorphicDefaultDeserializer(
        baseClass: KClass<Base>,
        defaultDeserializerProvider: (className: String?) -> DeserializationStrategy<Base>?
    ) {
        registerDefaultPolymorphicDeserializer(baseClass, defaultDeserializerProvider, false)
    }

    public fun include(module: SerializersModule) {
        module.dumpTo(this)
    }

    internal fun <T : Any> registerSerializer(
        forClass: KClass<T>,
        provider: ContextualProvider,
        allowOverwrite: Boolean = false
    ) {
        if (!allowOverwrite) {
            val previous = class2ContextualProvider[forClass]
            if (previous != null && previous != provider) {
                throw SerializerAlreadyRegisteredException(
                    "Contextual serializer or serializer provider for $forClass already registered in this module"
                )
            }
        }
        class2ContextualProvider[forClass] = provider
        if (forClass.isInterface) hasInterfaceContextualSerializers = true
    }

    internal fun <Base : Any> registerDefaultPolymorphicSerializer(
        baseClass: KClass<Base>,
        defaultSerializerProvider: (value: Base) -> SerializationStrategy<Base>?,
        allowOverwrite: Boolean
    ) {
        val previous = polyBase2DefaultSerializerProvider[baseClass]
        if (previous != null && previous != defaultSerializerProvider && !allowOverwrite) {
            throw IllegalArgumentException("Default serializers provider for $baseClass is already registered: $previous")
        }
        @Suppress("UNCHECKED_CAST")
        polyBase2DefaultSerializerProvider[baseClass] = defaultSerializerProvider as PolymorphicSerializerProvider<*>
    }

    internal fun <Base : Any> registerDefaultPolymorphicDeserializer(
        baseClass: KClass<Base>,
        defaultDeserializerProvider: (className: String?) -> DeserializationStrategy<Base>?,
        allowOverwrite: Boolean
    ) {
        val previous = polyBase2DefaultDeserializerProvider[baseClass]
        if (previous != null && previous != defaultDeserializerProvider && !allowOverwrite) {
            throw IllegalArgumentException("Default deserializer provider for $baseClass is already registered: $previous")
        }
        @Suppress("UNCHECKED_CAST")
        polyBase2DefaultDeserializerProvider[baseClass] = defaultDeserializerProvider as PolymorphicDeserializerProvider<*>
    }

    internal fun <Base : Any, Sub : Base> registerPolymorphicSerializer(
        baseClass: KClass<Base>,
        concreteClass: KClass<Sub>,
        concreteSerializer: KSerializer<Sub>,
        allowOverwrite: Boolean = false
    ) {
        val name = concreteSerializer.descriptor.serialName
        val baseClassSerializers = polyBase2Serializers.getOrPut(baseClass) { hashMapOf() }
        val names = polyBase2NamedSerializers.getOrPut(baseClass) { hashMapOf() }

        val previousSerializer = baseClassSerializers[concreteClass]
        if (previousSerializer != null && previousSerializer != concreteSerializer) {
            if (allowOverwrite) names.remove(previousSerializer.descriptor.serialName)
            else throw SerializerAlreadyRegisteredException(baseClass, concreteClass)
        }

        val previousByName = names[name]
        if (previousByName != null && previousByName != concreteSerializer) {
            val previousClass = baseClassSerializers.asSequence().find { it.value === previousByName }?.key
                ?: error("Name $name is registered in the module but no Kotlin class is associated with it.")

            if (allowOverwrite) baseClassSerializers.remove(previousClass)
            else throw IllegalArgumentException(
                "Multiple polymorphic serializers in a scope of '$baseClass' " +
                        "have the same serial name '$name': $concreteSerializer for '$concreteClass' and $previousByName for '$previousClass'"
            )
        }

        baseClassSerializers[concreteClass] = concreteSerializer
        names[name] = concreteSerializer
    }

    @PublishedApi
    internal fun build(): SerializersModule =
        SerialModuleImpl(class2ContextualProvider, polyBase2Serializers, polyBase2DefaultSerializerProvider, polyBase2NamedSerializers, polyBase2DefaultDeserializerProvider, hasInterfaceContextualSerializers)
}

public inline fun <reified T : Any> SerializersModuleBuilder.contextual(serializer: KSerializer<T>): Unit =
    contextual(T::class, serializer)

public inline fun <Base : Any> SerializersModuleBuilder.polymorphic(
    baseClass: KClass<Base>,
    baseSerializer: KSerializer<Base>? = null,
    builderAction: PolymorphicModuleBuilder<Base>.() -> Unit = {}
) {
    val builder = PolymorphicModuleBuilder(baseClass, baseSerializer)
    builder.builderAction()
    builder.buildTo(this)
}

private class SerializerAlreadyRegisteredException internal constructor(msg: String) : IllegalArgumentException(msg) {
    internal constructor(
        baseClass: KClass<*>,
        concreteClass: KClass<*>
    ) : this("Serializer for $concreteClass already registered in the scope of $baseClass")
}
