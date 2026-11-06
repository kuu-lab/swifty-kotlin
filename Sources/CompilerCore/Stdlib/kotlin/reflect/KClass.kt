/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KClass.kt.
 */

package kotlin.reflect

import kotlin.internal.KsSymbolName

// `isInstance` carries a default body so that call sites which bypass the
// KClass member-call lowering (implicit receivers, direct symbol calls)
// still reach the runtime bridge instead of the empty abstract stub.
@KsSymbolName("__kk_kclass_isInstance")
private external fun __kk_kclass_isInstance(kclass: KClass<*>, value: Any?): Boolean

/**
 * The KClass identity contract is supplied by the platform runtime.
 *
 * KClass handles are interned by the represented type token in this runtime,
 * so the existing Any equality and hashCode lowering provides the matching
 * value semantics for these declarations.
 */
public interface KClass<T : Any> : KAnnotatedElement, KClassifier, KDeclarationContainer {
    public val objectInstance: T?
    public val sealedSubclasses: List<KClass<out T>>
    public val constructors: Collection<KFunction<T>>

    public val simpleName: String?
    public val qualifiedName: String?

    public fun isInstance(value: Any?): Boolean = __kk_kclass_isInstance(this, value)

    public override fun equals(other: Any?): Boolean
    public override fun hashCode(): Int
}
