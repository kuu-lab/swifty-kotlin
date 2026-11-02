/*
 * Copyright 2017-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization

import kotlinx.serialization.descriptors.*
import kotlinx.serialization.encoding.*
import kotlin.reflect.KClass

// Upstream uses `KSerializer::class` as the [Serializable.with] default to mean "the
// auto-generated serializer". This toolchain cannot form a KClass literal for a type
// parameter whose bound is nullable (`KSerializer<Any?>` does not satisfy `KClass`'s
// `T : Any` bound), so a private sentinel object stands in for the same meaning.
private object GeneratedSerializerMarker : KSerializer<Any> {
    override val descriptor: SerialDescriptor
        get() = error("GeneratedSerializerMarker is only a marker for Serializable.with")

    override fun serialize(encoder: Encoder, value: Any) =
        error("GeneratedSerializerMarker is only a marker for Serializable.with")

    override fun deserialize(decoder: Decoder): Any =
        error("GeneratedSerializerMarker is only a marker for Serializable.with")
}

/**
 * Instructs the serialization plugin to use a generated or the given [with] serializer
 * for the annotated class, property or type usage.
 *
 * The `with` argument names a [KSerializer] implementation (e.g. `object UrlSerializer : KSerializer<Url>`).
 * Without a compiler plugin no `serializer()` is generated for the annotated class, so this
 * declaration only provides the API surface; an explicit `with =` argument is required for
 * serialization to actually work at runtime.
 */
@MustBeDocumented
@Target(AnnotationTarget.PROPERTY, AnnotationTarget.CLASS, AnnotationTarget.TYPE)
//@Retention(AnnotationRetention.RUNTIME) // Runtime is the default retention, also see KT-41082
public annotation class Serializable(
    val with: KClass<out KSerializer<*>> = GeneratedSerializerMarker::class // Default value indicates that auto-generated serializer is used
)

/**
 * The meta-annotation for adding [Serializable] behaviour to user-defined annotations.
 * Applying [MetaSerializable] to annotation class `A` instructs the serialization plugin
 * to treat `A` as [Serializable].
 */
@MustBeDocumented
@Target(AnnotationTarget.ANNOTATION_CLASS)
//@Retention(AnnotationRetention.RUNTIME) // Runtime is the default retention, also see KT-41082
@ExperimentalSerializationApi
public annotation class MetaSerializable

/**
 * Instructs the serialization plugin to turn this class into serializer for the specified class [forClass].
 * It is not used automatically; to apply it on a particular class or property,
 * use [Serializable] or [UseSerializers], or [Contextual] with runtime registration.
 */
@MustBeDocumented
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.BINARY)
@ExperimentalSerializationApi
public annotation class Serializer(
    val forClass: KClass<*>
)

@MustBeDocumented
@Target(AnnotationTarget.PROPERTY, AnnotationTarget.CLASS)
public annotation class SerialName(val value: String)

@MustBeDocumented
@Target(AnnotationTarget.ANNOTATION_CLASS)
@Retention(AnnotationRetention.BINARY)
@ExperimentalSerializationApi
public annotation class SerialInfo

@MustBeDocumented
@Target(AnnotationTarget.ANNOTATION_CLASS)
@Retention(AnnotationRetention.BINARY)
@ExperimentalSerializationApi
public annotation class InheritableSerialInfo

@MustBeDocumented
@Target(AnnotationTarget.PROPERTY)
public annotation class Required

@MustBeDocumented
@Target(AnnotationTarget.PROPERTY)
public annotation class Transient

@MustBeDocumented
@Target(AnnotationTarget.PROPERTY)
public annotation class EncodeDefault(val mode: Mode = Mode.ALWAYS) {
    public enum class Mode { ALWAYS, NEVER }
}

/**
 * Instructs the plugin to use a runtime-registered contextual serializer
 * on a given property or type usage.
 */
@Target(AnnotationTarget.PROPERTY, AnnotationTarget.TYPE)
@Retention(AnnotationRetention.BINARY)
public annotation class Contextual

/**
 * Instructs the plugin to use a contextual serializer for every type in the current file
 * that is listed in [forClasses].
 */
@Target(AnnotationTarget.FILE)
@Retention(AnnotationRetention.BINARY)
public annotation class UseContextualSerialization(vararg val forClasses: KClass<*>)

/**
 * Adds [serializerClasses] to the serializers resolving process inside the plugin.
 * Each of [serializerClasses] must implement [KSerializer].
 */
@Target(AnnotationTarget.FILE)
@Retention(AnnotationRetention.BINARY)
public annotation class UseSerializers(vararg val serializerClasses: KClass<out KSerializer<*>>)

/**
 * Instructs the serialization plugin to use a polymorphic serializer on an annotated
 * property, type usage or class.
 */
@Target(AnnotationTarget.PROPERTY, AnnotationTarget.TYPE, AnnotationTarget.CLASS)
//@Retention(AnnotationRetention.RUNTIME) // Runtime is the default retention, also see KT-41082
public annotation class Polymorphic

/**
 * Instructs the serialization plugin to keep the automatically generated [KSerializer]
 * implementation for the current class when a custom serializer is specified via
 * `@Serializable(with = ...)`. The generated serializer is then available via
 * `generatedSerializer()` in the companion object.
 */
@ExperimentalSerializationApi
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
public annotation class KeepGeneratedSerializer
