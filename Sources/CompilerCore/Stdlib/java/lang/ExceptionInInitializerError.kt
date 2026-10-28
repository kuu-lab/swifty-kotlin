package java.lang

import kotlin.Error
import kotlin.Throwable
import kotlin.internal.KsSymbolName

public open class ExceptionInInitializerError : Error {
    @KsSymbolName("__kk_exception_in_initializer_error_new")
    public constructor()

    @KsSymbolName("__kk_exception_in_initializer_error_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_exception_in_initializer_error_new_cause")
    public constructor(exception: Throwable?)
}
