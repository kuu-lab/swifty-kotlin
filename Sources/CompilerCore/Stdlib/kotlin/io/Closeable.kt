/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/io/Closeable.kt.
 */

package kotlin.io

import kotlin.AutoCloseable

// KSP-721: `kotlin.AutoCloseable` is now a source-backed interface in
// `Stdlib/kotlin/AutoCloseable.kt`. `kotlin.io.Closeable` extends `AutoCloseable`
// and redeclares `close()` so that the JVM-compatible `Closeable` subtype is
// preserved. `kotlin.io.use` remains a source-backed extension for `Closeable?`.

public interface Closeable : AutoCloseable {
    public override fun close()
}

public fun <T : Closeable?, R> T.use(block: (T) -> R): R {
    val resource = this
    val closeable: Closeable? = resource
    try {
        return block(resource)
    } finally {
        closeable?.close()
    }
}
