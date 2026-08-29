@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.ExperimentalAtomicApi

@ExperimentalAtomicApi
fun useExperimentalAtomicApi() {
    println("OK")
}

fun main() {
    useExperimentalAtomicApi()
}
