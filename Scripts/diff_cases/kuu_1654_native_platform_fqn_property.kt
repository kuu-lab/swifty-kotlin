// CANDIDATE-ONLY: kotlin.native.Platform has no JVM reference; compare the FQN read with imported and named-object reads.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.Platform as ShortPlatform

fun main() {
    val platform = ShortPlatform
    println(kotlin.native.Platform.isDebugBinary == ShortPlatform.isDebugBinary)
    println(kotlin.native.Platform.isDebugBinary == platform.isDebugBinary)
}
