package kotlin

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_assertions_enabled")
private external fun __kk_assertions_enabled(): Boolean

// KSwiftK keeps assertion argument evaluation enabled in generated programs.
public fun isAssertionArgumentEvaluationEnabled(): Boolean = true

// Mirrors kotlin.assert: a failed assertion throws only while assertions are enabled.
public fun isAssertionThrowingErrorEnabled(): Boolean = __kk_assertions_enabled()
