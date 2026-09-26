@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicReference

// KUU-858: CAS on AtomicReference<T> with value types must succeed when the
// caller's expected word is the same logical value — the erased-T boundary
// re-marshals it (raw Int payload vs fresh Int box, re-materialized String
// handle), so the runtime compares decoded payloads. Real reference types
// keep pointer identity.
fun main() {
    val strings = AtomicReference("aaa")
    val cur = strings.load()
    println(strings.compareAndSet(cur, "bbb"))
    println(strings.load())
    println(strings.compareAndSet("aaa", "ccc"))
    println(strings.load())
    println(strings.compareAndExchange("bbb", "ddd"))
    println(strings.load())

    val ints = AtomicReference(41)
    val icur = ints.load()
    println(ints.compareAndSet(icur, 42))
    println(ints.load())
    println(ints.compareAndExchange(42, 43))
    println(ints.load())
}
