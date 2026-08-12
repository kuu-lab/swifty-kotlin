package kotlin

import kotlin.internal.KsSymbolName

/**
 * An exception thrown when a not-yet-implemented operation is reached.
 *
 * The instance is allocated by the runtime so that `catch (e: NotImplementedError)`
 * can discriminate it from unrelated [Error] subclasses.
 */
public class NotImplementedError : kotlin.Error {
    @KsSymbolName("__kk_not_implemented_error_new")
    public constructor()

    @KsSymbolName("__kk_not_implemented_error_new_message")
    public constructor(message: String)
}

/** Always throws [NotImplementedError] to indicate that an operation is not implemented. */
public fun TODO(): Nothing = throw NotImplementedError()

/**
 * Always throws [NotImplementedError] to indicate that an operation is not implemented,
 * describing why via [reason].
 */
public fun TODO(reason: String): Nothing =
    throw NotImplementedError("An operation is not implemented: " + reason)

/** Throws [IllegalArgumentException] if [value] is false. */
public fun require(value: Boolean): Unit {
    if (!value) throw IllegalArgumentException("Failed requirement.")
}

/** Throws [IllegalArgumentException] with the result of [lazyMessage] if [value] is false. */
public fun require(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalArgumentException(lazyMessage().toString())
}

/** Throws [IllegalStateException] if [value] is false. */
public fun check(value: Boolean): Unit {
    if (!value) throw IllegalStateException("Check failed.")
}

/** Throws [IllegalStateException] with the result of [lazyMessage] if [value] is false. */
public fun check(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalStateException(lazyMessage().toString())
}

/** Throws [IllegalStateException] with [message]. */
public fun error(message: Any): Nothing = throw IllegalStateException(message.toString())

@KsSymbolName("__kk_assertions_enabled")
private external fun __kk_assertions_enabled(): Boolean

/** Throws [AssertionError] if [value] is false and assertions are enabled. */
public fun assert(value: Boolean): Unit {
    if (!__kk_assertions_enabled()) return
    if (!value) throw AssertionError("Assertion failed")
}

/** Throws [AssertionError] with the result of [lazyMessage] if [value] is false and assertions are enabled. */
public fun assert(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!__kk_assertions_enabled()) return
    if (!value) throw AssertionError(lazyMessage().toString())
}
