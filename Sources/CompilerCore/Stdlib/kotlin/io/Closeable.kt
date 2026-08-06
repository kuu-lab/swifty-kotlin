/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/io/Closeable.kt.
 */

package kotlin.io

import kotlin.internal.KsSymbolName

// KSP-611: Closeable / AutoCloseable / use are migrated to Kotlin source. The
// interface reuses the synthetic shell on bundle load so `TypeSystem.closeableTypeID`
// (a compiler residual used by the `.use {}` try-finally inline lowering in
// CallLowerer+ScopeFunctionLowering.swift) keeps pointing at the same symbol.
// The only remaining runtime bridge is the demoted __kk_auto_closeable_create
// factory (Sources/Runtime/RuntimeCollectionHOF.swift), which builds a Closeable
// whose close() invokes the given lambda.

public interface Closeable {
    public fun close()
}

@KsSymbolName("__kk_auto_closeable_create")
public external fun AutoCloseable(closeAction: () -> Unit): Closeable

public fun <T : Closeable?, R> T.use(block: (T) -> R): R {
    val resource = this
    val closeable: Closeable? = resource
    try {
        return block(resource)
    } finally {
        closeable?.close()
    }
}
