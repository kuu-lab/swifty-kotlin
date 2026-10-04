// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are not available in the kotlinc diff reference environment.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
@file:Suppress("DEPRECATION")

import kotlin.native.Platform

fun main() {
    println(Platform.canAccessUnaligned)
    println(Platform.isLittleEndian)
    println(Platform.osFamily)
    println(Platform.cpuArchitecture)
    println(Platform.memoryModel)
    println(Platform.isDebugBinary)
    println(Platform.isFreezingEnabled)
    println(Platform.programName)
    println(Platform.isMemoryLeakCheckerActive)
    Platform.isMemoryLeakCheckerActive = false
    println(Platform.isCleanersLeakCheckerActive)
    Platform.isCleanersLeakCheckerActive = false
    println(Platform.getAvailableProcessors())
}
