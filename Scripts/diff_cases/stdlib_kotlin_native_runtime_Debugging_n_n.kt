// CANDIDATE-ONLY: kotlin.native.runtime APIs are Kotlin/Native-only and have no JVM reference output.
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.Debugging

fun debuggingSingleton(): Debugging = Debugging

fun main() {
    println(debuggingSingleton() === Debugging)
}
