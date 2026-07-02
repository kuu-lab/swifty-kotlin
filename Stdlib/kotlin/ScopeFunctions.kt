@file:Suppress("NOTHING_TO_INLINE")

package kotlin

inline fun <T, R> T.let(block: (T) -> R): R =
    block(this)

inline fun <T, R> T.run(block: T.() -> R): R =
    block()

inline fun <R> run(block: () -> R): R =
    block()

inline fun <T> T.also(block: (T) -> Unit): T {
    block(this)
    return this
}

inline fun <T> T.apply(block: T.() -> Unit): T {
    block()
    return this
}

inline fun <T, R> with(receiver: T, block: T.() -> R): R =
    receiver.block()

inline fun <T> T.takeIf(predicate: (T) -> Boolean): T? =
    if (predicate(this)) this else null

inline fun <T> T.takeUnless(predicate: (T) -> Boolean): T? =
    if (!predicate(this)) this else null
