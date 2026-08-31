@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
@file:Suppress("DEPRECATION")

import kotlin.native.Platform

fun platformContract(): Int {
    val unaligned: Boolean = Platform.canAccessUnaligned
    val littleEndian: Boolean = Platform.isLittleEndian
    val osFamily = Platform.osFamily
    val cpuArchitecture = Platform.cpuArchitecture
    val memoryModel = Platform.memoryModel
    val debugBinary: Boolean = Platform.isDebugBinary
    val freezingEnabled: Boolean = Platform.isFreezingEnabled
    val programName: String? = Platform.programName
    val leakChecker: Boolean = Platform.isMemoryLeakCheckerActive
    Platform.isMemoryLeakCheckerActive = !leakChecker
    val cleanersChecker: Boolean = Platform.isCleanersLeakCheckerActive
    Platform.isCleanersLeakCheckerActive = !cleanersChecker
    return Platform.getAvailableProcessors() +
        if (unaligned || littleEndian || debugBinary || freezingEnabled || programName != null) 1 else 0 +
        if (osFamily == osFamily && cpuArchitecture == cpuArchitecture && memoryModel == memoryModel) 1 else 0
}
