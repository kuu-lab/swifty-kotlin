@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicReference

fun atomicReferenceConstructorSemantics(): String {
    val intRef = AtomicReference(41)
    val stringRef = AtomicReference("initial")
    return "${intRef.load()}:${stringRef.load()}"
}
