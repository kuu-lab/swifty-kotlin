/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/Core.kt (tag 0.9.1). `SystemLineSeparator` is `expect` in
 * upstream; this compiler has a single (POSIX-like) target, so it is a plain constant here.
 */
package kotlinx.io

/**
 * Returns a new source that buffers reads from this source.
 */
public fun RawSource.buffered(): Source = RealSource(this)

/**
 * Returns a new sink that buffers writes to this sink.
 */
public fun RawSink.buffered(): Sink = RealSink(this)

/**
 * Returns a sink that discards all data written to it.
 */
public fun discardingSink(): RawSink = DiscardingSink()

private class DiscardingSink : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        source.skip(byteCount)
    }

    override fun flush() {
    }

    override fun close() {
    }
}

public val SystemLineSeparator: String = "\n"
