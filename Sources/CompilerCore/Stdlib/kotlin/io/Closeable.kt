/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/io/Closeable.kt.
 */

package kotlin.io

import kotlin.AutoCloseable
import kotlin.internal.KsSymbolName

// KSP-721: `kotlin.io.Closeable` redeclares `close()` so that the
// JVM-compatible `Closeable` subtype is preserved.

public interface Closeable : AutoCloseable {
    public override fun close()
}

// KUU-3449: `Closeable { }` SAM factory, mirroring the
// `AutoCloseable(closeAction)` external factory (KSP-721). The shared
// `__kk_closeable_create` bridge also serves the `java.io.Closeable`
// factory (Stdlib/java/io/Closeable.kt); the returned box answers
// `close()` dispatched through either Closeable nominal.
@KsSymbolName("__kk_closeable_create")
public external fun Closeable(closeAction: () -> Unit): Closeable

public fun <T : Closeable?, R> T.use(block: (T) -> R): R {
    val resource = this
    val closeable: Closeable? = resource
    try {
        return block(resource)
    } finally {
        closeable?.close()
    }
}
