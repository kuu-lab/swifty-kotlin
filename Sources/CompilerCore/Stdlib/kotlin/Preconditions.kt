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

public fun TODO(): Nothing = throw NotImplementedError()

public fun TODO(reason: String): Nothing =
    throw NotImplementedError("An operation is not implemented: " + reason)

public fun require(value: Boolean): Unit {
    if (!value) throw IllegalArgumentException("Failed requirement.")
}

public fun require(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalArgumentException(lazyMessage().toString())
}

public fun check(value: Boolean): Unit {
    if (!value) throw IllegalStateException("Check failed.")
}

public fun check(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalStateException(lazyMessage().toString())
}

public fun error(message: Any): Nothing = throw IllegalStateException(message.toString())

@KsSymbolName("__kk_assertions_enabled")
private external fun __kk_assertions_enabled(): Boolean

public fun assert(value: Boolean): Unit {
    if (!__kk_assertions_enabled()) return
    if (!value) throw AssertionError("Assertion failed")
}

public fun assert(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!__kk_assertions_enabled()) return
    if (!value) throw AssertionError(lazyMessage().toString())
}

@OptIn(ExperimentalContracts::class)
public fun <T : Any> requireNotNull(value: T?): T {
    contract { returns() implies (value != null) }
    if (value == null) throw IllegalArgumentException("Required value was null.")
    return value as T
}

@OptIn(ExperimentalContracts::class)
public fun <T : Any> requireNotNull(value: T?, lazyMessage: () -> Any): T {
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
