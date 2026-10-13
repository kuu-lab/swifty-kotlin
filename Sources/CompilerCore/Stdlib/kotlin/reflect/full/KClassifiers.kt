/*
 * Copyright 2010-2016 JetBrains s.r.o.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-reflect libraries/stdlib/.../kotlin/reflect/full/KClassifiers.kt.
 */

package kotlin.reflect.full

import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass
import kotlin.reflect.KClassifier
import kotlin.reflect.KType
import kotlin.reflect.KTypeProjection
import kotlin.reflect.typeParameters

@KsSymbolName("__kk_ktype_create")
private external fun __kk_ktype_create(
    classifier: KClassifier,
    arguments: List<KTypeProjection>,
    isNullable: Int
): KType

private fun KClassifier.declaredTypeParameterCount(): Int {
    val klass = this as? KClass<*> ?: return 0
    val parameters: List<Any?> = klass.typeParameters
    return parameters.size
}

/**
 * Creates a [KType] instance with the given classifier, type arguments, nullability and annotations.
 * If the number of passed type arguments is not equal to the total number of type parameters of a classifier,
 * an exception is thrown.
 */
public fun KClassifier.createType(
    arguments: List<KTypeProjection> = emptyList(),
    nullable: Boolean = false,
    annotations: List<Annotation> = emptyList()
): KType {
    val parameterCount = declaredTypeParameterCount()
    if (parameterCount != arguments.size) {
        throw IllegalArgumentException(
            "Class declares $parameterCount type parameters, but ${arguments.size} were provided."
        )
    }
    return __kk_ktype_create(this, arguments, if (nullable) 1 else 0)
}

/**
 * Creates an instance of [KType] with the given classifier, substituting all its type parameters with star projections.
 * The resulting type is not marked as nullable and does not have any annotations.
 */
public val KClassifier.starProjectedType: KType
    get() {
        val parameterCount = declaredTypeParameterCount()
        val arguments = mutableListOf<KTypeProjection>()
        var index = 0
        while (index < parameterCount) {
            arguments.add(KTypeProjection.STAR)
            index += 1
        }
        return __kk_ktype_create(this, arguments, 0)
    }
