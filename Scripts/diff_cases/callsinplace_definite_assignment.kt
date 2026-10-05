@file:OptIn(kotlin.contracts.ExperimentalContracts::class)

import kotlin.contracts.InvocationKind
import kotlin.contracts.contract

// STDLIB-592 follow-up: `contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }`
// (and `AT_LEAST_ONCE`) must let definite-assignment analysis treat an uninitialized
// outer `var` assigned inside the lambda argument as initialized after the call
// returns, the same way it would for a plain sequential block.

inline fun once(block: () -> Unit) {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    block()
}

inline fun atLeastOnce(block: () -> Unit) {
    contract { callsInPlace(block, InvocationKind.AT_LEAST_ONCE) }
    block()
    block()
}

inline fun readFromHead(block: (Int) -> Int): Int {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    return block(0)
}

fun read(block: (Int) -> Int): Int {
    var result: Int
    readFromHead { array ->
        result = block(array)
        result
    }
    return result
}

inline fun readBufferHead(start: Int, end: Int, block: (Int, Int) -> Int): Int {
    contract { callsInPlace(block, InvocationKind.AT_LEAST_ONCE) }
    block(start, end)
    return block(start + 1, end)
}

fun readBuffer(block: (Int, Int) -> Int): Int {
    var result: Int
    readBufferHead(block = { start, end ->
        result = block(start, end)
        result
    }, end = 9, start = 2)
    return result
}

fun viaCustomExactlyOnce(): Int {
    var result: Int
    once { result = 7 }
    return result
}

fun viaCustomAtLeastOnce(): Int {
    var result: Int
    atLeastOnce { result = 9 }
    return result
}

fun viaFreeRun(): Int {
    var r: Int
    run { r = 3 }
    return r
}

fun viaFreeWith(): Int {
    var w: Int
    with("hi") { w = length }
    return w
}

fun viaMemberLet(): Int {
    var l: Int
    "hello".let { l = it.length }
    return l
}

fun viaMemberApply(): Int {
    var a: Int
    42.apply { a = this }
    return a
}

fun viaMemberAlso(): Int {
    var s: Int
    "world".also { s = it.length }
    return s
}

fun viaMemberRun(): Int {
    var m: Int
    "abcde".run { m = length }
    return m
}

fun main() {
    println(read { it + 42 })
    println(readBuffer { start, end -> end - start })
    println(viaCustomExactlyOnce())
    println(viaCustomAtLeastOnce())
    println(viaFreeRun())
    println(viaFreeWith())
    println(viaMemberLet())
    println(viaMemberApply())
    println(viaMemberAlso())
    println(viaMemberRun())
}
