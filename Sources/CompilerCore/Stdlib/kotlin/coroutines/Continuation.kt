/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/Continuation.kt.
 */

package kotlin.coroutines

// KSP-1131: keep the public nominal declarations in bundled Kotlin source.
// Constructors and members remain owned by their dedicated coroutine TODOs.
public interface Continuation<in T>
