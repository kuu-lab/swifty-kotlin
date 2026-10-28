package kotlin

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract
import kotlin.internal.KsSymbolName

/**
 * The instance is allocated by the runtime so that `catch (e: NotImplementedError)`
 * can discriminate it from unrelated [Error] subclasses.
 */
public class NotImplementedError : kotlin.Error {
    @KsSymbolName("__kk_not_implemented_error_new")
    public constructor()

    @KsSymbolName("__kk_not_implemented_error_new_message")
    public constructor(message: String)
}

public inline fun TODO(): Nothing = throw NotImplementedError()

public inline fun TODO(reason: String): Nothing =
    throw NotImplementedError("An operation is not implemented: " + reason)

public inline fun require(value: Boolean): Unit {
    if (!value) throw IllegalArgumentException("Failed requirement.")
}

public inline fun require(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalArgumentException(lazyMessage().toString())
}

public inline fun check(value: Boolean): Unit {
    if (!value) throw IllegalStateException("Check failed.")
}

public inline fun check(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalStateException(lazyMessage().toString())
}

public inline fun error(message: Any): Nothing = throw IllegalStateException(message.toString())

@KsSymbolName("__kk_assertions_enabled")
@PublishedApi
internal external fun __kk_assertions_enabled(): Boolean

public inline fun assert(value: Boolean): Unit {
    if (!__kk_assertions_enabled()) return
    if (!value) throw AssertionError("Assertion failed")
}

public inline fun assert(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!__kk_assertions_enabled()) return
    if (!value) throw AssertionError(lazyMessage().toString())
}

@OptIn(ExperimentalContracts::class)
public inline fun <T : Any> requireNotNull(value: T?): T {
    contract { returns() implies (value != null) }
    if (value == null) throw IllegalArgumentException("Required value was null.")
    return value as T
}

@OptIn(ExperimentalContracts::class)
public inline fun <T : Any> requireNotNull(value: T?, lazyMessage: () -> Any): T {
    contract { returns() implies (value != null) }
    if (value == null) throw IllegalArgumentException(lazyMessage().toString())
    return value as T
}

@OptIn(ExperimentalContracts::class)
public inline fun <T : Any> checkNotNull(value: T?): T {
    contract { returns() implies (value != null) }
    if (value == null) throw IllegalStateException("Required value was null.")
    return value as T
}

@OptIn(ExperimentalContracts::class)
public inline fun <T : Any> checkNotNull(value: T?, lazyMessage: () -> Any): T {
    contract { returns() implies (value != null) }
    if (value == null) throw IllegalStateException(lazyMessage().toString())
    return value as T
}
