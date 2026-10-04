/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 * Copyright (C) 2014 Square, Inc. Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-io core/common/src/SegmentPool.kt (tag 0.9.1). Upstream declares an
 * `expect object`; this compiler has a single target, so this mirrors upstream's native actual:
 * a no-op pool that always allocates fresh segments and never recycles.
 */
package kotlinx.io

/**
 * A collection of unused segments, necessary to avoid GC churn and zero-fill.
 * This pool is a thread-safe static singleton.
 */
internal object SegmentPool {
    val MAX_SIZE: Int = 0

    /**
     * For testing only. Returns a snapshot of the number of bytes currently in the pool. If the pool
     * is segmented such as by thread, this returns the byte count accessible to the calling thread.
     */
    val byteCount: Int = 0

    /** Return a segment for the caller's use. */
    fun take(): Segment = Segment.new()

    /** Recycle a segment that the caller no longer needs. */
    fun recycle(segment: Segment) {
    }

    /**
     * Allocates a new copy tracker that'll be associated with a segment from this pool.
     * For performance reasons, there's no tracker attached to a segment initially.
     * Instead, it's allocated lazily on the first sharing attempt.
     */
    fun tracker(): SegmentCopyTracker = AlwaysSharedCopyTracker
}
