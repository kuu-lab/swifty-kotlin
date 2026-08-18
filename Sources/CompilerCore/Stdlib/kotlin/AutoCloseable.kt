/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/AutoCloseable.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

public interface AutoCloseable {
    public fun close()
}

@KsSymbolName("__kk_auto_closeable_create")
public external fun AutoCloseable(closeAction: () -> Unit): AutoCloseable

public inline fun <T : AutoCloseable?, R> T.use(block: (T) -> R): R {
    val resource = this
    val closeable: AutoCloseable? = resource
    try {
        return block(resource)
    } finally {
        closeable?.close()
    }
}
