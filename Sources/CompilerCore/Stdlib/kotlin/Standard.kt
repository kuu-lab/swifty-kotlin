package kotlin

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

public inline fun <T, R> with(receiver: T, block: T.() -> R): R = receiver.block()

public inline fun <R> run(block: () -> R): R = block()

public inline fun <T, R> T.run(block: T.() -> R): R = block()

public inline fun <T, R> T.runCatching(block: T.() -> R): Result<R> {
    val receiver = this
    return runCatching { receiver.run { block() } }
}

public inline fun <T> T.apply(block: T.() -> Unit): T {
    block()
    return this
}

public inline fun <T, R> T.let(block: (T) -> R): R = block(this)

public inline fun <T> T.also(block: (T) -> Unit): T {
    block(this)
    return this
}

public inline fun <T> T.takeIf(predicate: (T) -> Boolean): T? =
    if (predicate(this)) this else null

public inline fun <T> T.takeUnless(predicate: (T) -> Boolean): T? =
    if (!predicate(this)) this else null
