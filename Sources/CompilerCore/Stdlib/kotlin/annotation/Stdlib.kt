/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotation/Annotations.kt>.
 */

package kotlin.annotation

/** Contains the list of code elements which are possible annotation targets. */
public enum class AnnotationTarget {
    CLASS,
    ANNOTATION_CLASS,
    TYPE_PARAMETER,
    PROPERTY,
    FIELD,
    LOCAL_VARIABLE,
    VALUE_PARAMETER,
    CONSTRUCTOR,
    FUNCTION,
    PROPERTY_GETTER,
    PROPERTY_SETTER,
    TYPE,
    EXPRESSION,
    FILE,
    @SinceKotlin("1.1")
    TYPEALIAS
}

/** Contains the list of possible annotation retentions. */
public enum class AnnotationRetention {
    SOURCE,
    BINARY,
    RUNTIME
}

/** Specifies the code elements which are possible targets of an annotation. */
@Target(AnnotationTarget.ANNOTATION_CLASS)
@MustBeDocumented
public annotation class Target(vararg val allowedTargets: AnnotationTarget)

/** Specifies whether an annotation is stored in binary output and visible for reflection. */
@Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class Retention(val value: AnnotationRetention = AnnotationRetention.RUNTIME)

/** Specifies that an annotation is applicable twice or more on a single code element. */
@Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class Repeatable

/** Specifies that an annotation is part of the public API and should be documented. */
@Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class MustBeDocumented
