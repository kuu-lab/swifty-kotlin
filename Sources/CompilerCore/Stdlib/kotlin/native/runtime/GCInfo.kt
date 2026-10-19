/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/GCInfo.kt>.
 */

package kotlin.native.runtime

// Kotlin/Native reports the total allocated object size in bytes, excluding
// system allocator overhead while including alignment and object headers.
@NativeRuntimeApi
@SinceKotlin("1.9")
public class MemoryUsage(
    public val totalObjectsSizeBytes: Long,
)

@NativeRuntimeApi
@SinceKotlin("1.9")
public class SweepStatistics(
    public val sweptCount: Long,
    public val keptCount: Long,
)

@NativeRuntimeApi
@SinceKotlin("1.9")
public class RootSetStatistics(
    public val threadLocalReferences: Long,
    public val stackReferences: Long,
    public val globalReferences: Long,
    public val stableReferences: Long,
)

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
