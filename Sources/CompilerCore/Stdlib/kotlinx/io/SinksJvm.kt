/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/jvm/src/SinksJvm.kt (tag 0.9.1). Only `Sink.asOutputStream()` is
 * ported; upstream's `writeString`/`write(ByteBuffer)`/`asByteChannel` depend on not-yet-ported
 * APIs. The synthetic `java.io.OutputStream` cannot be subclassed or constructed from Kotlin
 * source, so the stream is a bridge object built by `__kk_kotlin_sink_output_stream` that
 * invokes the callbacks below; upstream's anonymous `OutputStream` subclass becomes a Kotlin
 * callback closure per operation.
 */
package kotlinx.io

import java.io.OutputStream
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_kotlin_sink_output_stream")
private external fun kkKotlinSinkOutputStream(
    writeBytes: (ByteArray) -> Unit,
    flushAction: () -> Unit,
    closeAction: () -> Unit
): OutputStream

/**
 * Returns an output stream that writes to this sink.
 *
 * Upstream keeps no stream-side closed flag either: writes surface
 * `IOException("Underlying sink is closed.")` only when the sink reports
 * itself closed (`RealSink`), flushes become no-ops, and `close()` just
 * delegates to `Sink.close()`. A `Buffer` never reports closed, so writes
 * keep flowing even after the stream is closed — matching upstream.
 *
 * The thrown type is `java.io.IOException` — upstream's `kotlinx.io.IOException`
 * is a typealias for it, and in this compiler the runtime-backed
 * `java.io.IOException` is the catchable spelling for the colliding
 * `IOException` name. It is referenced qualified because an unqualified
 * `IOException` inside `kotlinx.io` resolves to the bundled class of the same
 * name.
 */
public fun Sink.asOutputStream(): OutputStream {
    val sink = this
    val isClosed: () -> Boolean = when (sink) {
        is RealSink -> { { sink.closed } }
        is Buffer -> { { false } }
        else -> { { false } }
    }
    return kkKotlinSinkOutputStream(
        { bytes: ByteArray ->
            if (isClosed()) throw java.io.IOException("Underlying sink is closed.")
            sink.write(bytes, 0, bytes.size)
        },
        { if (!isClosed()) sink.flush() },
        { sink.close() }
    )
}
