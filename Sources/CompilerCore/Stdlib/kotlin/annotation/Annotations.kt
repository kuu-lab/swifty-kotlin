/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotation/Annotations.kt>.
 */

package kotlin.annotation

import kotlin.enums.enumEntries

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

public enum class AnnotationRetention {
    SOURCE,
    BINARY,
    RUNTIME
}

public val AnnotationTarget.entries: kotlin.enums.EnumEntries<AnnotationTarget>
    get() = enumEntries<AnnotationTarget>()

public val AnnotationRetention.entries: kotlin.enums.EnumEntries<AnnotationRetention>
    get() = enumEntries<AnnotationRetention>()

@Target(AnnotationTarget.ANNOTATION_CLASS)
@MustBeDocumented
public annotation class Target(vararg val allowedTargets: AnnotationTarget)

@Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class Retention(val value: AnnotationRetention = AnnotationRetention.RUNTIME)

@Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class Repeatable

@Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class MustBeDocumented
