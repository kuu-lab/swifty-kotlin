@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicReference

// KUU-858: CAS on AtomicReference<T> with value types must succeed when the
// caller's expected word is the same logical value — the erased-T boundary
// re-marshals primitives (raw Int payload vs fresh Int box), so the runtime
// compares decoded primitive payloads. Strings preserve their canonical
// object handles through flat bridges and keep reference identity.
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
