/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/GCInfo.kt>.
 */

package kotlin.native.runtime

// KSP-1267: Keep the native GC memory-pool measurement source-backed.
// Kotlin/Native reports the total allocated object size in bytes, excluding
// system allocator overhead while including alignment and object headers.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class MemoryUsage(
    public val totalObjectsSizeBytes: Long,
)

// KSP-1272: Keep both native GC sweep counters source-backed and immutable.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class SweepStatistics(
    public val sweptCount: Long,
    public val keptCount: Long,
)

// KSP-1269: source-back the public RootSetStatistics nominal declaration and
// constructor. Its residual property surface remains synthetic until KSP-1270.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class RootSetStatistics(
    threadLocalReferences: Long,
    stackReferences: Long,
    globalReferences: Long,
    stableReferences: Long,
)

// KSP-1264: source-back the public GCInfo nominal declaration and constructor.
// Its property surface remains synthetic until KSP-1265.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class GCInfo(
    epoch: Long,
    startTimeNs: Long,
    endTimeNs: Long,
    firstPauseRequestTimeNs: Long,
    firstPauseStartTimeNs: Long,
    firstPauseEndTimeNs: Long,
    secondPauseRequestTimeNs: Long?,
    secondPauseStartTimeNs: Long?,
    secondPauseEndTimeNs: Long?,
    postGcCleanupTimeNs: Long?,
    rootSet: RootSetStatistics,
    markedCount: Long,
    sweepStatistics: Map<String, SweepStatistics>,
    memoryUsageBefore: Map<String, MemoryUsage>,
    memoryUsageAfter: Map<String, MemoryUsage>,
)
