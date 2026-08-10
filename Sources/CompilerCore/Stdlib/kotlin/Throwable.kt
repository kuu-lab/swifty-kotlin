package kotlin

import kotlin.internal.KsSymbolName

/**
 * The base class for all errors and exceptions. Only instances of this class
 * can be thrown or caught.
 *
 * The actual storage is allocated by the runtime as a boxed exception object;
 * the Kotlin-level class declares the type, its public constructor surface and
 * its members. Members are expressed in Kotlin and reach the boxed storage
 * through the small `__kk_throwable_*` accessor bridges below. The mutating /
 * suppressed-list members are declared as extensions so that call sites keep
 * static dispatch: runtime-allocated throwable boxes carry no Kotlin vtable.
 */
public open class Throwable {
    @KsSymbolName("__kk_throwable_new")
    public constructor()

    @KsSymbolName("__kk_throwable_new")
    public constructor(message: String?)

    @KsSymbolName("__kk_throwable_new_with_cause")
    public constructor(message: String?, cause: Throwable?)

    public val message: String?
        get() = __kkThrowableMessage(this)

    public val cause: Throwable?
        get() = __kkThrowableCause(this)
}

public fun Throwable.initCause(cause: Throwable?): Throwable {
    __kkThrowableSetCause(this, cause)
    return this
}

public fun Throwable.addSuppressed(exception: Throwable) {
    if (exception !== this) {
        __kkThrowableAppendSuppressed(this, exception)
    }
}

public fun Throwable.getSuppressed(): Array<Throwable> = __kkThrowableSuppressedRaw(this)

public val Throwable.suppressedExceptions: List<Throwable>
    get() = __kkThrowableSuppressedRaw(this).toList()

@KsSymbolName("__kk_throwable_message")
internal external fun __kkThrowableMessage(throwable: Throwable): String?

@KsSymbolName("__kk_throwable_cause")
internal external fun __kkThrowableCause(throwable: Throwable): Throwable?

@KsSymbolName("__kk_throwable_setCause")
internal external fun __kkThrowableSetCause(throwable: Throwable, cause: Throwable?)

@KsSymbolName("__kk_throwable_appendSuppressed")
internal external fun __kkThrowableAppendSuppressed(throwable: Throwable, exception: Throwable)

@KsSymbolName("__kk_throwable_suppressedRaw")
internal external fun __kkThrowableSuppressedRaw(throwable: Throwable): Array<Throwable>
