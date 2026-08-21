/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib core/builtins/native/kotlin/CharSequence.kt.
 */

package kotlin

// KSP-724: nominal `kotlin.CharSequence` declaration migrated out of the
// synthetic self-registration; on bundle load it reuses the synthetic shell.
// `get` and `subSequence` are kept as extension functions in `kotlin.text`
// so that the interface has no method slots and the runtime CharSequence
// itable `length` getter stays at property slot 0.
public interface CharSequence {
    public val length: Int
}
