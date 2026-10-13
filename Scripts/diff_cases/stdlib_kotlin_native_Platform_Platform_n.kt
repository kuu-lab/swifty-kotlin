// DIFF_CANDIDATE_ONLY: kotlin.native.Platform has no JVM kotlinc reference.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_Platform_Platform_n.expected.stdout
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlin.native.Platform

fun main() {
    println(Platform.canAccessUnaligned == Platform.canAccessUnaligned)
    println(Platform.isLittleEndian == Platform.isLittleEndian)
    println(Platform.osFamily == Platform.osFamily)
    println(Platform.cpuArchitecture == Platform.cpuArchitecture)
    println(Platform.memoryModel == Platform.memoryModel)
    println(Platform.isDebugBinary == Platform.isDebugBinary)
    println(Platform.isFreezingEnabled == Platform.isFreezingEnabled)
    println(Platform.programName == Platform.programName)

    val leakChecker = Platform.isMemoryLeakCheckerActive
    Platform.isMemoryLeakCheckerActive = !leakChecker
    println(Platform.isMemoryLeakCheckerActive == !leakChecker)
    Platform.isMemoryLeakCheckerActive = leakChecker

    val cleanersLeakChecker = Platform.isCleanersLeakCheckerActive
    Platform.isCleanersLeakCheckerActive = !cleanersLeakChecker
    println(Platform.isCleanersLeakCheckerActive == !cleanersLeakChecker)
    Platform.isCleanersLeakCheckerActive = cleanersLeakChecker

    println(Platform.getAvailableProcessors() > 0)
}
