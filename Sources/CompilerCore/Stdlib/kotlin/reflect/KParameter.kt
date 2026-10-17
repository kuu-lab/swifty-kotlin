/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/reflect/KParameter.kt.
 */

package kotlin.reflect

// The member properties below are backed by the runtime KParameter box and
// dispatch through the `__kk_kparameter_*` bridges via the member-access
// fast path in CallLowerer+KCallableMemberCalls.swift.

public interface KParameter : KAnnotatedElement {
    public val index: Int

    public val name: String?

    /**
     * For a `vararg` parameter, this is the type of the corresponding array,
     * not the individual element.
     */
    public val type: KType

    public val kind: Kind

    public enum class Kind {
        INSTANCE,

        @ExperimentalContextParameters
        CONTEXT,

        EXTENSION_RECEIVER,

        VALUE,
    }

    public val isOptional: Boolean

    @SinceKotlin("1.1")
    public val isVararg: Boolean
}
