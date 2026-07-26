package kotlin

import kotlin.internal.KsSymbolName

/**
 * The base class for all errors and exceptions. Only instances of this class
 * can be thrown or caught.
 *
 * The actual storage is allocated by the runtime as a boxed exception object;
 * the Kotlin-level class only declares the type and its public constructor
 * surface.
 */
public open class Throwable {
    @KsSymbolName("__kk_throwable_new")
    public constructor()

    @KsSymbolName("__kk_throwable_new")
    public constructor(message: String?)

    @KsSymbolName("__kk_throwable_new_with_cause")
    public constructor(message: String?, cause: Throwable?)
}
