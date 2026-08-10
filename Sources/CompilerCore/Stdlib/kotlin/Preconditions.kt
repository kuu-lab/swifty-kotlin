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
