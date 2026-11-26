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

internal object SegmentPool {
    val MAX_SIZE: Int = 0

    val byteCount: Int = 0

    fun take(): Segment = Segment.new()

    fun recycle(segment: Segment) {
    }

    fun tracker(): SegmentCopyTracker = AlwaysSharedCopyTracker
}
