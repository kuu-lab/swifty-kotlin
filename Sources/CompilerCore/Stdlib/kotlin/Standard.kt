package kotlin

/**
 * Kotlin standard scope functions and conditional wrappers.
 *
 * These are implemented as bundled Kotlin source and are inline-expanded at
 * call sites; they have no runtime entry points.
 */

public inline fun <T, R> T.let(block: (T) -> R): R = block(this)

public inline fun <T> T.also(block: (T) -> Unit): T {
    block(this)
    return this
}

public inline fun <T> T.takeIf(predicate: (T) -> Boolean): T? =
    if (predicate(this)) this else null

public inline fun <T> T.takeUnless(predicate: (T) -> Boolean): T? =
    if (!predicate(this)) this else null
