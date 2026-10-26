/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KFunction.kt.
 */

package kotlin.reflect

import kotlin.internal.KsSymbolName

public interface KFunction<out R> : KCallable<R>, Function<R>

// KFunction1 is synthesized by the Kotlin compiler alongside function types.
// Declare its arity-specific shape so imports and inherited function/reflection
// supertypes resolve in this bundled source as well.
public interface KFunction1<in P1, out R> : KFunction<R>, (P1) -> R
// KUU-1357: the KFunction modifier flags are extension properties here for the
// same reason the KClass surface uses extensions — runtime-backed handles
// dispatch through the `__kk_kfunction_*` bridges rather than an interface
// itable. `isSuspend`/`isAbstract`/`isFinal`/`isOpen`/`visibility` are declared
// on `KCallable` and dispatch through the callable-metadata fast path.

@KsSymbolName("__kk_kfunction_is_inline")
private external fun __kk_kfunction_is_inline(kfunction: KFunction<*>): Boolean

@KsSymbolName("__kk_kfunction_is_operator")
private external fun __kk_kfunction_is_operator(kfunction: KFunction<*>): Boolean

@KsSymbolName("__kk_kfunction_is_infix")
private external fun __kk_kfunction_is_infix(kfunction: KFunction<*>): Boolean

@KsSymbolName("__kk_kfunction_is_external")
private external fun __kk_kfunction_is_external(kfunction: KFunction<*>): Boolean

public val KFunction<*>.isInline: Boolean
    get() = __kk_kfunction_is_inline(this)

public val KFunction<*>.isOperator: Boolean
    get() = __kk_kfunction_is_operator(this)

public val KFunction<*>.isInfix: Boolean
    get() = __kk_kfunction_is_infix(this)

public val KFunction<*>.isExternal: Boolean
    get() = __kk_kfunction_is_external(this)
