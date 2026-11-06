// KUU-4214: kotlinx-coroutines Builders.kt relies on the same
// explicit-import/same-package overload merge inside
// `Sequence<T>.asFlow() = flow { }`, where the extension receiver adds a
// second implicit receiver to the call. The builder-interception path used
// to resolve `flow { }` against the package-tier candidate alone, so the
// imported `channelFlow as flow` never joined the overload set and the
// Flow<T> return type failed.
package kuu4214.test

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow as flow

class Box<T> {
    fun send(value: T) {}
}

fun <T> flow(block: suspend Box<T>.() -> Unit): String = "same-package"

fun <T> Sequence<T>.asFlow(): Flow<T> = flow { }

fun main() {
    val f: Flow<Int> = listOf(1, 2, 3).asSequence().asFlow()
    println("ok")
}
