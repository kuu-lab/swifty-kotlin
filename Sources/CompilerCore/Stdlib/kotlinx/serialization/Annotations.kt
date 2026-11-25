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

@MustBeDocumented
@Target(AnnotationTarget.PROPERTY, AnnotationTarget.CLASS, AnnotationTarget.TYPE)
//@Retention(AnnotationRetention.RUNTIME) // Runtime is the default retention, also see KT-41082
public annotation class Serializable(
    val with: KClass<out KSerializer<*>> = GeneratedSerializerMarker::class
)

@MustBeDocumented
@Target(AnnotationTarget.ANNOTATION_CLASS)
//@Retention(AnnotationRetention.RUNTIME) // Runtime is the default retention, also see KT-41082
@ExperimentalSerializationApi
public annotation class MetaSerializable

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

@Target(AnnotationTarget.PROPERTY, AnnotationTarget.TYPE)
@Retention(AnnotationRetention.BINARY)
public annotation class Contextual

@Target(AnnotationTarget.FILE)
@Retention(AnnotationRetention.BINARY)
public annotation class UseContextualSerialization(vararg val forClasses: KClass<*>)

@Target(AnnotationTarget.FILE)
@Retention(AnnotationRetention.BINARY)
public annotation class UseSerializers(vararg val serializerClasses: KClass<out KSerializer<*>>)

@Target(AnnotationTarget.PROPERTY, AnnotationTarget.TYPE, AnnotationTarget.CLASS)
//@Retention(AnnotationRetention.RUNTIME) // Runtime is the default retention, also see KT-41082
public annotation class Polymorphic

@ExperimentalSerializationApi
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
public annotation class KeepGeneratedSerializer
