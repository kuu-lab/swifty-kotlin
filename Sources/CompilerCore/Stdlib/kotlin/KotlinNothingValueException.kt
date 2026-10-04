package kotlin

import kotlin.internal.KsSymbolName

// KSP-742: bundled Kotlin source for KotlinNothingValueException.

public class KotlinNothingValueException : RuntimeException {
    @KsSymbolName("__kk_kotlin_nothing_value_exception_new")
    public constructor()

    @KsSymbolName("__kk_kotlin_nothing_value_exception_new_message")
    public constructor(message: String?)

    @KsSymbolName("__kk_kotlin_nothing_value_exception_new_message_cause")
    public constructor(message: String?, cause: Throwable?)

    @KsSymbolName("__kk_kotlin_nothing_value_exception_new_cause")
    public constructor(cause: Throwable?)
}
