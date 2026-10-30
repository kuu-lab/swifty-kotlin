/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KFunction.kt.
 */

package kotlin.reflect

import kotlin.internal.KsSymbolName

public interface KFunction<out R> : KCallable<R>, Function<R>

// KFunctionN is synthesized by the Kotlin compiler alongside function types.
// Declare the arity-specific shapes so imports and inherited
// function/reflection supertypes resolve in this bundled source as well.
public interface KFunction0<out R> : KFunction<R>, () -> R
public interface KFunction1<in P1, out R> : KFunction<R>, (P1) -> R
public interface KFunction2<in P1, in P2, out R> : KFunction<R>, (P1, P2) -> R
public interface KFunction3<in P1, in P2, in P3, out R> : KFunction<R>, (P1, P2, P3) -> R
public interface KFunction4<in P1, in P2, in P3, in P4, out R> : KFunction<R>, (P1, P2, P3, P4) -> R
public interface KFunction5<in P1, in P2, in P3, in P4, in P5, out R> : KFunction<R>, (P1, P2, P3, P4, P5) -> R
public interface KFunction6<in P1, in P2, in P3, in P4, in P5, in P6, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6) -> R
public interface KFunction7<in P1, in P2, in P3, in P4, in P5, in P6, in P7, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7) -> R
public interface KFunction8<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8) -> R
public interface KFunction9<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9) -> R
public interface KFunction10<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10) -> R
public interface KFunction11<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11) -> R
public interface KFunction12<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12) -> R
public interface KFunction13<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13) -> R
public interface KFunction14<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14) -> R
public interface KFunction15<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15) -> R
public interface KFunction16<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, in P16, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15, P16) -> R
public interface KFunction17<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, in P16, in P17, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15, P16, P17) -> R
public interface KFunction18<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, in P16, in P17, in P18, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15, P16, P17, P18) -> R
public interface KFunction19<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, in P16, in P17, in P18, in P19, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15, P16, P17, P18, P19) -> R
public interface KFunction20<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, in P16, in P17, in P18, in P19, in P20, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15, P16, P17, P18, P19, P20) -> R
public interface KFunction21<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, in P16, in P17, in P18, in P19, in P20, in P21, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15, P16, P17, P18, P19, P20, P21) -> R
public interface KFunction22<in P1, in P2, in P3, in P4, in P5, in P6, in P7, in P8, in P9, in P10, in P11, in P12, in P13, in P14, in P15, in P16, in P17, in P18, in P19, in P20, in P21, in P22, out R> : KFunction<R>, (P1, P2, P3, P4, P5, P6, P7, P8, P9, P10, P11, P12, P13, P14, P15, P16, P17, P18, P19, P20, P21, P22) -> R
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
