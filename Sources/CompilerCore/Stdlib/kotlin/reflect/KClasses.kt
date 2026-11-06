/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KClasses.kt.
 */

package kotlin.reflect

import kotlin.internal.KsSymbolName

// `__kk_kclass_cast` is a throwing runtime entry (`isThrowing: true` in
// RuntimeABISpec+Operator.swift); ABILoweringPass appends the `outThrown`
// argument automatically, so the Kotlin declaration lists only the two value
// parameters.
@KsSymbolName("__kk_kclass_cast")
private external fun __kk_kclass_cast(kclass: KClass<*>, value: Any?): Any?

@KsSymbolName("__kk_kclass_safeCast")
private external fun __kk_kclass_safeCast(kclass: KClass<*>, value: Any?): Any?

@KsSymbolName("__kk_kclass_is_enum")
private external fun __kk_kclass_is_enum(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_interface")
private external fun __kk_kclass_is_interface(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_object")
private external fun __kk_kclass_is_object(kclass: KClass<*>): Boolean

// Upstream marks the kotlin.reflect cast/safeCast extensions
// @LowPriorityInOverloadResolution so the kotlin.reflect.full overloads win
// when both are visible (stdlib KClasses.kt). Mirroring that here keeps
// unqualified `k.cast(v)` unambiguous now that both packages declare them.
@kotlin.internal.LowPriorityInOverloadResolution
public fun <T : Any> KClass<T>.cast(value: Any?): T =
    __kk_kclass_cast(this, value) as T

@kotlin.internal.LowPriorityInOverloadResolution
public fun <T : Any> KClass<T>.safeCast(value: Any?): T? =
    __kk_kclass_safeCast(this, value) as T?

public val KClass<*>.isEnum: Boolean
    get() = __kk_kclass_is_enum(this)

public val KClass<*>.isInterface: Boolean
    get() = __kk_kclass_is_interface(this)

public val KClass<*>.isObject: Boolean
    get() = __kk_kclass_is_object(this)

// NOTE (KUU-1357): the collection accessors below carry their real upstream
// element types (`Collection<KCallable<*>>`, `Collection<KClass<*>>`,
// `List<KType>`, …) — the returned runtime handles carry stable reflection
// nominal IDs (KSP-689), so `is`/`as` and shared `KCallable` metadata
// dispatch are valid at the Kotlin boundary.
//
// `findAnnotation<T>()` is declared in reflect/full/KAnnotatedElements.kt
// with the upstream KAnnotatedElement receiver. Its resolved KClass calls
// use the native annotation lookup; other receivers execute the inline body.
// `findAssociatedObject<T>()` remains a reified compiler special case,
// with its source declaration in AssociatedObjects.kt.
//
// NOTE: `properties` is also NOT covered here, unlike its `memberProperties`/
// `declaredMemberProperties` siblings. It is not a real kotlin-stdlib name
// (only the `member`/`declaredMember`-prefixed variants exist upstream), and
// Scripts/diff_cases/kclass_interface_handles.kt relies on being able to
// freely shadow it with a real user-declared extension for kotlinc
// portability. It remains a compiler special case so user shadowing keeps
// working exactly as before.

@KsSymbolName("__kk_kclass_member_properties")
private external fun __kk_kclass_member_properties(kclass: KClass<*>): List<KProperty<*>>

@KsSymbolName("__kk_kclass_declared_member_properties")
private external fun __kk_kclass_declared_member_properties(kclass: KClass<*>): List<KProperty<*>>

@KsSymbolName("__kk_kclass_functions")
private external fun __kk_kclass_functions(kclass: KClass<*>): List<KFunction<*>>

@KsSymbolName("__kk_kclass_member_functions")
private external fun __kk_kclass_member_functions(kclass: KClass<*>): List<KFunction<*>>

@KsSymbolName("__kk_kclass_declared_member_functions")
private external fun __kk_kclass_declared_member_functions(kclass: KClass<*>): List<KFunction<*>>

@KsSymbolName("__kk_kclass_companion_object")
private external fun __kk_kclass_companion_object(kclass: KClass<*>): Any?

public val KClass<*>.memberProperties: Collection<KProperty<*>>
    get() = __kk_kclass_member_properties(this)

public val KClass<*>.declaredMemberProperties: Collection<KProperty<*>>
    get() = __kk_kclass_declared_member_properties(this)

public val KClass<*>.functions: Collection<KFunction<*>>
    get() = __kk_kclass_functions(this)

public val KClass<*>.memberFunctions: Collection<KFunction<*>>
    get() = __kk_kclass_member_functions(this)

public val KClass<*>.declaredMemberFunctions: Collection<KFunction<*>>
    get() = __kk_kclass_declared_member_functions(this)

public val KClass<*>.companionObject: KClass<*>?
    get() = __kk_kclass_companion_object(this) as? KClass<*>
