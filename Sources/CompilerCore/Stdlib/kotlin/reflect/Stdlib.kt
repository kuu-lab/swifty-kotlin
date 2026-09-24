/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/reflect/>.
 */

package kotlin.reflect

// KSP-1323: source-backed kotlin.reflect top-level surfaces. Runtime reflection
// boxes implement these interfaces through the native interface itable; member
// declarations owned by follow-up KSP entries remain registered by the residual
// synthetic pass in the meantime.

/**
 * An annotation that designates a property or a function returning a key for
 * associated object lookup.
 */
@kotlin.reflect.ExperimentalAssociatedObjects
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class AssociatedObjectKey

/**
 * Represents an annotated element and allows to obtain its annotations.
 */
public interface KAnnotatedElement

/**
 * A classifier is either a class or a type parameter.
 */
public interface KClassifier

/**
 * Represents an entity which may contain declarations of other entities.
 */
public interface KDeclarationContainer

/**
 * Represents a function accessible by reflection.
 */
public interface KFunction<out R> : KCallable<R>, Function<R>

/**
 * Represents a property, accessible as a getter.
 */
public interface KProperty<out V> : KCallable<V>

/**
 * Represents a property which can be changed.
 */
public interface KMutableProperty<V> : KProperty<V>

/**
 * Represents a type parameter of a generic declaration.
 */
public interface KTypeParameter : KClassifier

/**
 * Returns a runtime representation of the given reified type [T] as an instance of [KType].
 */
public inline fun <reified T> typeOf(): KType =
    throw IllegalStateException("typeOf is expanded by the compiler")
