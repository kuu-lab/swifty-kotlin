/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/modules/SerializersModuleCollector.kt.
 */

package kotlinx.serialization.modules

import kotlinx.serialization.*
import kotlin.reflect.*

/**
 * [SerializersModuleCollector] is a receiver for [SerializersModule.dumpTo] method.
 * It is used to copy the content of [SerializersModule] to [SerializersModuleBuilder] or other custom implementations.
 */
@ExperimentalSerializationApi
public interface SerializersModuleCollector {

    /**
     * Accept a serializer, associated with [kClass] for contextual serialization.
     */
    public fun <T : Any> contextual(kClass: KClass<T>, serializer: KSerializer<T>)

    /**
     * Accept a provider, associated with generic [kClass] for contextual serialization.
     */
    public fun <T : Any> contextual(
        kClass: KClass<T>,
        provider: (typeArgumentsSerializers: List<KSerializer<*>>) -> KSerializer<*>
    )

    /**
     * Accept a serializer, associated with [actualClass] for polymorphic serialization.
     */
    public fun <Base : Any, Sub : Base> polymorphic(
        baseClass: KClass<Base>,
        actualClass: KClass<Sub>,
        actualSerializer: KSerializer<Sub>
    )

    /**
     * Accept a default serializer provider, associated with the [baseClass] for polymorphic serialization.
     * [defaultSerializerProvider] is invoked when no polymorphic serializers for `value` in the scope of [baseClass] were found.
     */
    public fun <Base : Any> polymorphicDefaultSerializer(
        baseClass: KClass<Base>,
        defaultSerializerProvider: (value: Base) -> SerializationStrategy<Base>?
    )

    /**
     * Accept a default deserializer provider, associated with the [baseClass] for polymorphic deserialization.
     * [defaultDeserializerProvider] is invoked when no polymorphic serializers associated with the `className`
     * in the scope of [baseClass] were found.
     */
    public fun <Base : Any> polymorphicDefaultDeserializer(
        baseClass: KClass<Base>,
        defaultDeserializerProvider: (className: String?) -> DeserializationStrategy<Base>?
    )

    /**
     * Accept a default deserializer provider, associated with the [baseClass] for polymorphic deserialization.
     *
     * This function affects only deserialization process. To avoid confusion, it was deprecated and replaced with
     * [polymorphicDefaultDeserializer]. To affect serialization process, use
     * [SerializersModuleCollector.polymorphicDefaultSerializer].
     */
    @Deprecated(
        "Deprecated in favor of function with more precise name: polymorphicDefaultDeserializer",
        ReplaceWith("polymorphicDefaultDeserializer(baseClass, defaultDeserializerProvider)"),
        DeprecationLevel.WARNING // Since 1.5.0. Raise to ERROR in 1.6.0, hide in 1.7.0
    )
    public fun <Base : Any> polymorphicDefault(
        baseClass: KClass<Base>,
        defaultDeserializerProvider: (className: String?) -> DeserializationStrategy<Base>?
    ) {
        polymorphicDefaultDeserializer(baseClass, defaultDeserializerProvider)
    }
}
