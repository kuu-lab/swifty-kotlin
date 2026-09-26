/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/RawSink.kt (tag 0.9.1).
 * kotlinx-io declares this as `expect interface`; this compiler has a single target, so it is a
 * plain interface here.
 */
package kotlinx.io

/**
 * Receives a stream of bytes. RawSink is a base interface for `kotlinx-io` data receivers.
 */
public interface RawSink : AutoCloseable {
    /**
     * Removes [byteCount] bytes from [source] and appends them to this sink.
     */
    public fun write(source: Buffer, byteCount: Long)

    /**
     * Pushes all buffered bytes to their final destination.
     */
    public fun flush()

    override fun close()
}
