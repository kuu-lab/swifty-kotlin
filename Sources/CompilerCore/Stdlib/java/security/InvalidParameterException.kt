package java.security

import kotlin.internal.KsSymbolName

/** Thrown when an invalid parameter is passed to a method. */
public open class InvalidParameterException : java.lang.IllegalArgumentException {
    @KsSymbolName("__kk_invalid_parameter_exception_new")
    public constructor()

    @KsSymbolName("__kk_invalid_parameter_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_invalid_parameter_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_invalid_parameter_exception_new_cause")
    public constructor(cause: Throwable?)
}
