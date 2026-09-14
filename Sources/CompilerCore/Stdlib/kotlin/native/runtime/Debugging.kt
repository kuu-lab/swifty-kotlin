/*
 * KSP-1259: Source-backed nominal declaration for Kotlin/Native Debugging.
 *
 * The Debugging member surface (dumpMemory / forceCheckedShutdown /
 * isThreadStateRunnable / gcSuspendCount / threadCount / globalObjectCount)
 * remains owned by KSP-1260's migration; this file only source-backs the
 * top-level object itself.
 */

package kotlin.native.runtime

@NativeRuntimeApi
@SinceKotlin("1.9")
public object Debugging {}
