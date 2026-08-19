/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib commonMain/kotlin/util/Suspend.kt.
 */

package kotlin

// KSP-787: Build a suspend function value from a suspend lambda without adding
// a runtime bridge. The inline identity body preserves the lambda's suspend type.
public inline fun <R> suspend(noinline block: suspend () -> R): suspend () -> R = block
