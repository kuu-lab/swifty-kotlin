@file:OptIn(
    kotlin.experimental.ExperimentalNativeApi::class,
    kotlin.ExperimentalStdlibApi::class,
    kotlin.experimental.ExperimentalObjCName::class,
    kotlin.experimental.ExperimentalObjCRefinement::class,
    kotlin.native.SymbolNameIsInternal::class,
    kotlin.native.ObsoleteNativeApi::class,
)
@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.BitSet
import kotlin.native.CName
import kotlin.native.CpuArchitecture
import kotlin.native.EagerInitialization
import kotlin.native.FreezingIsDeprecated
import kotlin.native.HiddenFromObjC
import kotlin.native.HidesFromObjC
import kotlin.native.ImmutableBlob
import kotlin.native.IncorrectDereferenceException
import kotlin.native.MemoryModel
import kotlin.native.NoInline
import kotlin.native.ObjCName
import kotlin.native.ObsoleteNativeApi
import kotlin.native.OsFamily
import kotlin.native.Platform
import kotlin.native.RefinesInSwift
import kotlin.native.ReportUnhandledExceptionHook
import kotlin.native.ShouldRefineInSwift
import kotlin.native.SymbolName
import kotlin.native.getUnhandledExceptionHook
import kotlin.native.immutableBlobOf
import kotlin.native.initRuntimeIfNeeded
import kotlin.native.isExperimentalMM
import kotlin.native.processUnhandledException
import kotlin.native.setUnhandledExceptionHook
import kotlin.native.terminateWithUnhandledException
import kotlin.native.vectorOf

@RefinesInSwift
annotation class SwiftRefined

@CName(externName = "native_top_level", shortName = "native_top_level")
@ObjCName(name = "NativeTopLevel", swiftName = "NativeTopLevel", exact = true)
@HidesFromObjC
@HiddenFromObjC
@ShouldRefineInSwift
@FreezingIsDeprecated
@NoInline
@SymbolName("native_top_level")
fun nativeTopLevel(): Int = 42

@EagerInitialization
val eagerTopLevel = 1

fun nativeTopLevelSurface(
    osFamily: OsFamily,
    architecture: CpuArchitecture,
    memoryModel: MemoryModel,
    blob: ImmutableBlob?,
    hook: ReportUnhandledExceptionHook?,
    bitSet: BitSet,
    error: IncorrectDereferenceException,
): Int {
    val platformModel = Platform.memoryModel
    val currentHook = getUnhandledExceptionHook()
    val previousHook = setUnhandledExceptionHook(hook)
    initRuntimeIfNeeded()
    processUnhandledException(error)
    val floatVector = vectorOf(1.0f, 2.0f, 3.0f, 4.0f)
    val intVector = vectorOf(1, 2, 3, 4)
    val createdBlob = immutableBlobOf(1, 2, 3)
    return if (
        isExperimentalMM() &&
        platformModel == MemoryModel.EXPERIMENTAL &&
        currentHook === previousHook &&
        blob === createdBlob &&
        floatVector === intVector &&
        bitSet.size >= 0 &&
        osFamily == OsFamily.UNKNOWN &&
        architecture == CpuArchitecture.UNKNOWN
    ) 1 else 0
}

fun terminateTopLevel(error: Throwable): Nothing = terminateWithUnhandledException(error)
