/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KCallable.kt.
 */

package kotlin.reflect

/**
 * Represents a callable entity, such as a function or a property.
 *
 * The runtime supplies metadata for compiler-generated callable references.
 */
public interface KCallable<out R> : KAnnotatedElement {
    public val name: String
    public val parameters: List<KParameter>
    public val returnType: KType
    public val typeParameters: List<KTypeParameter>
    public fun call(vararg args: Any?): R
    public fun callBy(args: Map<KParameter, Any?>): R
    public val visibility: KVisibility?
    public val isFinal: Boolean
    public val isOpen: Boolean
    public val isAbstract: Boolean
    public val isSuspend: Boolean
}

internal class CallableTypeParameter(
    override val name: String,
    override val upperBounds: List<KType>,
    override val variance: KVariance,
    override val isReified: Boolean
) : KTypeParameter

internal fun callableTypeParameter(
    name: String, upperBounds: List<KType>, variance: KVariance, isReified: Boolean
): KTypeParameter = CallableTypeParameter(name, upperBounds, variance, isReified)
