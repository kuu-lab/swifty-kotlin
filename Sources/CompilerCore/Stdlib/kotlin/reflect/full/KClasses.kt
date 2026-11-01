/*
 * Copyright 2010-2016 JetBrains s.r.o.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-reflect libraries/stdlib/.../kotlin/reflect/full/KClasses.kt.
 */

package kotlin.reflect.full

import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass
import kotlin.reflect.KFunction
import kotlin.reflect.KProperty2
import kotlin.reflect.KType
import kotlin.reflect.isInstance
import kotlin.reflect.qualifiedName

@SinceKotlin("1.1")
@Suppress("UNCHECKED_CAST")
public fun <T : Any> KClass<T>.cast(value: Any?): T {
    if (!isInstance(value)) throw TypeCastException("Value cannot be cast to $qualifiedName")
    return value as T
}

@SinceKotlin("1.1")
@Suppress("UNCHECKED_CAST")
public fun <T : Any> KClass<T>.safeCast(value: Any?): T? =
    if (isInstance(value)) value as T else null

@KsSymbolName("__kk_kclass_primary_constructor")
private external fun __kk_kclass_primary_constructor(kclass: KClass<*>): Any?

public val <T : Any> KClass<T>.primaryConstructor: KFunction<T>?
    @Suppress("UNCHECKED_CAST")
    get() = __kk_kclass_primary_constructor(this) as? KFunction<T>

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

public fun KClass<*>.isSuperclassOf(derived: KClass<*>): Boolean =
    derived.isSubclassOf(this)

// KUU-4064: member-extension accessors. The JVM keeps `val String.x` /
// `fun String.f()` declared inside a class out of `member*`/`declaredMember*`
// and surfaces them only through these `memberExtension*` queries.
@KsSymbolName("__kk_kclass_member_extension_properties")
private external fun __kk_kclass_member_extension_properties(kclass: KClass<*>): List<KProperty2<*, *, *>>

@KsSymbolName("__kk_kclass_declared_member_extension_properties")
private external fun __kk_kclass_declared_member_extension_properties(kclass: KClass<*>): List<KProperty2<*, *, *>>

@KsSymbolName("__kk_kclass_member_extension_functions")
private external fun __kk_kclass_member_extension_functions(kclass: KClass<*>): List<KFunction<*>>

@KsSymbolName("__kk_kclass_declared_member_extension_functions")
private external fun __kk_kclass_declared_member_extension_functions(kclass: KClass<*>): List<KFunction<*>>

@SinceKotlin("1.1")
public val <T : Any> KClass<T>.memberExtensionProperties: Collection<KProperty2<T, *, *>>
    @Suppress("UNCHECKED_CAST")
    get() = __kk_kclass_member_extension_properties(this) as Collection<KProperty2<T, *, *>>

@SinceKotlin("1.1")
public val <T : Any> KClass<T>.declaredMemberExtensionProperties: Collection<KProperty2<T, *, *>>
    @Suppress("UNCHECKED_CAST")
    get() = __kk_kclass_declared_member_extension_properties(this) as Collection<KProperty2<T, *, *>>

@SinceKotlin("1.1")
public val <T : Any> KClass<T>.memberExtensionFunctions: Collection<KFunction<*>>
    get() = __kk_kclass_member_extension_functions(this)

@SinceKotlin("1.1")
public val <T : Any> KClass<T>.declaredMemberExtensionFunctions: Collection<KFunction<*>>
    get() = __kk_kclass_declared_member_extension_functions(this)
