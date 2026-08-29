/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib core/builtins/native/kotlin/CharSequence.kt.
 */

package kotlin

// KSP-724: nominal `kotlin.CharSequence` declaration migrated out of the
// synthetic self-registration; on bundle load it reuses the synthetic shell.
// `subSequence` remains an extension function in `kotlin.text`; `get` is a
// nominal interface member so user-defined CharSequence implementations and
// interface-typed receivers use the normal member-dispatch path.
public interface CharSequence {
    public val length: Int
    public operator fun get(index: Int): Char
}
