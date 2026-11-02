/*
 * Copyright 2017-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization

import kotlin.reflect.KClass

/** Marks a declaration for serialization metadata and optional custom serializer selection. */
@MustBeDocumented
@Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY, AnnotationTarget.TYPE)
public annotation class Serializable(
    val with: KClass<out KSerializer<*>> = KSerializer::class
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
