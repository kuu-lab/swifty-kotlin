package kotlin

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract

/**
 * Kotlin standard scope functions, conditional wrappers, and stdlib utilities.
 *
 * These are implemented as bundled Kotlin source and are inline-expanded at
 * call sites; they have no runtime entry points.
 */

// KSP-604: `repeat` migrated from the synthetic stdlib loop stub. It stays
// `inline` so that suspend calls inside `action` remain in the enclosing suspend
// function and can be coroutine-lowered.
public inline fun repeat(times: Int, action: (Int) -> Unit) {
    var index = 0
    while (index < times) {
        action(index)
        index += 1
    }
}

@OptIn(ExperimentalContracts::class)
public inline fun <T, R> with(receiver: T, block: T.() -> R): R {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    return receiver.block()
}

@OptIn(ExperimentalContracts::class)
public inline fun <R> run(block: () -> R): R {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    return block()
}

@OptIn(ExperimentalContracts::class)
public inline fun <T, R> T.run(block: T.() -> R): R {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    return block()
}

public inline fun <T, R> T.runCatching(block: T.() -> R): Result<R> {
    val receiver = this
    return __kkRuntimeResultRunCatching { receiver.run { block() } }
}

@OptIn(ExperimentalContracts::class)
public inline fun <T> T.apply(block: T.() -> Unit): T {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    block()
    return this
}

@OptIn(ExperimentalContracts::class)
public inline fun <T, R> T.let(block: (T) -> R): R {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    return block(this)
}

@OptIn(ExperimentalContracts::class)
public inline fun <T> T.also(block: (T) -> Unit): T {
    contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
    block(this)
    return this
}

public inline fun <T> T.takeIf(predicate: (T) -> Boolean): T? =
    if (predicate(this)) this else null

public inline fun <T> T.takeUnless(predicate: (T) -> Boolean): T? =
    if (!predicate(this)) this else null
