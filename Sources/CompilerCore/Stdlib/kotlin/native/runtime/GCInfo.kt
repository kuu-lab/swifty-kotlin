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

// KSP-1269/KSP-1270: Keep the native GC root-set statistics DTO source-backed
// and immutable, matching upstream GCInfo.kt.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class RootSetStatistics(
    public val threadLocalReferences: Long,
    public val stackReferences: Long,
    public val globalReferences: Long,
    public val stableReferences: Long,
)

// KSP-1265: Keep the GC pause/heap statistics DTO's full property surface
// source-backed and immutable, matching upstream GCInfo.kt.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class GCInfo(
    public val epoch: Long,
    public val startTimeNs: Long,
    public val endTimeNs: Long,
    public val firstPauseRequestTimeNs: Long,
    public val firstPauseStartTimeNs: Long,
    public val firstPauseEndTimeNs: Long,
    public val secondPauseRequestTimeNs: Long?,
    public val secondPauseStartTimeNs: Long?,
    public val secondPauseEndTimeNs: Long?,
    public val postGcCleanupTimeNs: Long?,
    public val rootSet: RootSetStatistics,
    public val markedCount: Long,
    public val sweepStatistics: Map<String, SweepStatistics>,
    public val memoryUsageBefore: Map<String, MemoryUsage>,
    public val memoryUsageAfter: Map<String, MemoryUsage>,
)
