package kotlin

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_assertions_enabled")
private external fun __kk_assertions_enabled(): Boolean

public fun isAssertionArgumentEvaluationEnabled(): Boolean = true

public fun isAssertionThrowingErrorEnabled(): Boolean = __kk_assertions_enabled()
