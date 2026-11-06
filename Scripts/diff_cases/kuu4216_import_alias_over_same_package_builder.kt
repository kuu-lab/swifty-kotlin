// KUU-4216: an explicit import must join the same overload set as a
// same-package top-level function, and win when both are applicable
// (kotlinx-coroutines Builders.kt relies on `unsafeFlow as flow` shadowing
// the public `flow` builder inside the file). The builder-interception
// path used to resolve the call against the package-tier candidate alone,
// so `channelFlow { }` bound to the same-package overload and the
// Flow<Int> ascription failed.
package kuu4216.test

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow

class Box<T> {
    fun send(value: T) {}
}

fun <T> channelFlow(block: suspend Box<T>.() -> Unit): String = "same-package"

fun main() {
    val f: Flow<Int> = channelFlow { send(1) }
    println("ok")
}
