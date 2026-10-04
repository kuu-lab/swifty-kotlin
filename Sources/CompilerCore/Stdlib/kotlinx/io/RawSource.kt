/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/RawSource.kt (tag 0.9.1).
 */
package kotlinx.io

/**
 * Supplies a stream of bytes. RawSource is a base interface for `kotlinx-io` data suppliers.
 */
public interface RawSource : AutoCloseable {
    /**
     * Removes at least 1, and up to [byteCount] bytes from this source and appends them to [sink].
     * Returns the number of bytes read, or -1 if this source is exhausted.
     */
    public fun readAtMostTo(sink: Buffer, byteCount: Long): Long

    override fun close()
}
