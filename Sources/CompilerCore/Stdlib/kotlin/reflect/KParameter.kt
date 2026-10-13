/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/reflect/KParameter.kt.
 */

package kotlin.reflect

// KUU-1364: source-backed kotlin.reflect surface, following the same
// KSP-1323 per-declaration file layout as the neighbouring reflect files.
// The member properties below are backed by the runtime KParameter box and
// dispatch through the `__kk_kparameter_*` bridges via the member-access
// fast path in CallLowerer+KCallableMemberCalls.swift.

/**
 * Represents a parameter passed to a function or a property getter/setter,
 * including `this` and extension receiver parameters.
 */
public interface KParameter : KAnnotatedElement {
    /**
     * 0-based index of this parameter in the parameter list of its containing
     * callable.
     */
    public val index: Int

    /**
     * Name of this parameter as it was declared in the source code,
     * or `null` if the parameter has no name or its name is not available
     * at runtime.
     */
    public val name: String?

    /**
     * Type of this parameter. For a `vararg` parameter, this is the type of
     * the corresponding array, not the individual element.
     */
    public val type: KType

    /**
     * Kind of this parameter.
     */
    public val kind: Kind

    /**
     * Kind represents a particular position of the parameter declaration in
     * the source code, such as an instance, an extension receiver parameter
     * or a value parameter.
     */
    public enum class Kind {
        /** Instance parameter of a member callable. */
        INSTANCE,

        /** Context parameter of a callable. */
        @ExperimentalContextParameters
        CONTEXT,

        /** Extension receiver parameter of an extension callable. */
        EXTENSION_RECEIVER,

        /** Ordinary named parameter of a callable. */
        VALUE,
    }

    /**
     * `true` if this parameter is optional and can be omitted when making a
     * call via [KCallable.callBy], or `false` otherwise.
     */
    public val isOptional: Boolean

    /**
     * `true` if this parameter is `vararg`.
     */
    @SinceKotlin("1.1")
    public val isVararg: Boolean
}
