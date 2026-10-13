/*
 * Copyright 2010-2016 JetBrains s.r.o.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-reflect libraries/stdlib/.../kotlin/reflect/full/KClasses.kt.
 */

package kotlin.reflect.full

import kotlin.reflect.KClass
import kotlin.reflect.KFunction
import kotlin.reflect.KType

/**
 * Creates a new instance of the class, calling a constructor which either has no parameters or all
 * parameters of which are optional.
 * If there are no or many such constructors, an exception is thrown.
 */
public fun <T : Any> KClass<T>.createInstance(): T {
    var chosen: KFunction<*>? = null
    for (candidate in constructors) {
        val function = candidate as? KFunction<*> ?: continue
        if (function.parameters.all { it.isOptional }) {
            if (chosen != null) {
                throw IllegalArgumentException("Class should have a single no-arg constructor: $this")
            }
            chosen = function
        }
    }
    val noArgsConstructor = chosen
        ?: throw IllegalArgumentException("Class should have a single no-arg constructor: $this")
    @Suppress("UNCHECKED_CAST")
    return noArgsConstructor.callBy(emptyMap()) as T
}

/**
 * Returns `true` if `this` class is the same or is a (possibly indirect) subclass of [base], `false` otherwise.
 */
public fun KClass<*>.isSubclassOf(base: KClass<*>): Boolean {
    if (this == base) return true
    val visited = mutableListOf<KClass<*>>()
    val queue = mutableListOf<KClass<*>>()
    queue.add(this)
    visited.add(this)
    var head = 0
    while (head < queue.size) {
        val current = queue[head]
        head += 1
        for (supertype in current.supertypes) {
            val classifier = (supertype as KType).classifier as? KClass<*> ?: continue
            if (classifier == base) return true
            if (!visited.contains(classifier)) {
                visited.add(classifier)
                queue.add(classifier)
            }
        }
    }
    return false
}

/**
 * Returns `true` if `this` class is the same or is a (possibly indirect) superclass of [derived], `false` otherwise.
 */
public fun KClass<*>.isSuperclassOf(derived: KClass<*>): Boolean =
    derived.isSubclassOf(this)
