/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/modules/SerializersModuleCollector.kt.
 */

package kotlinx.serialization.modules

import kotlinx.serialization.*
import kotlin.reflect.*

@ExperimentalSerializationApi
public interface SerializersModuleCollector {

    public fun <T : Any> contextual(kClass: KClass<T>, serializer: KSerializer<T>)

    public fun <T : Any> contextual(
        kClass: KClass<T>,
        provider: (typeArgumentsSerializers: List<KSerializer<*>>) -> KSerializer<*>
    )

    public fun <Base : Any, Sub : Base> polymorphic(
        baseClass: KClass<Base>,
        actualClass: KClass<Sub>,
        actualSerializer: KSerializer<Sub>
    )

    public fun <Base : Any> polymorphicDefaultSerializer(
        baseClass: KClass<Base>,
        defaultSerializerProvider: (value: Base) -> SerializationStrategy<Base>?
    )

    public fun <Base : Any> polymorphicDefaultDeserializer(
        baseClass: KClass<Base>,
        defaultDeserializerProvider: (className: String?) -> DeserializationStrategy<Base>?
    )

    @Deprecated(
        "Deprecated in favor of function with more precise name: polymorphicDefaultDeserializer",
        ReplaceWith("polymorphicDefaultDeserializer(baseClass, defaultDeserializerProvider)"),
        DeprecationLevel.WARNING
    )
    public fun <Base : Any> polymorphicDefault(
        baseClass: KClass<Base>,
        defaultDeserializerProvider: (className: String?) -> DeserializationStrategy<Base>?
    ) {
        polymorphicDefaultDeserializer(baseClass, defaultDeserializerProvider)
    }
}
