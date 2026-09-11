/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/CoroutinesH.kt.
 */

package kotlin.coroutines

// KSP-1131: keep the public nominal declarations in bundled Kotlin source.
// Constructors and members remain owned by their dedicated coroutine TODOs.
public interface Continuation<in T>

// ContinuationInterceptor already lives in ContinuationInterceptor/Stdlib.kt
// (KSP-1140); redeclaring it here collides in the same package scope.

public interface CoroutineContext

public interface SuspendFunction<out R>

// AbstractCoroutineContextElement already lives in
// AbstractCoroutineContextElement/Stdlib.kt (KSP-1136); redeclaring it here
// collides in the same package scope.

// AbstractCoroutineContextKey already lives in AbstractCoroutineContextKey/Stdlib.kt
// (KSP-1138); redeclaring it here collides in the same package scope.
