/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test <libraries/kotlin.test/common/src/main/kotlin/kotlin/test/Utils.kt>
 * and <kotlin-native/runtime/src/main/kotlin/kotlin/test/Assertions.kt> (Kotlin 2.3.10).
 */

package kotlin.test

internal fun messagePrefix(message: String?): String = if (message == null) "" else "$message. "

internal fun lookupAsserter(): Asserter = DefaultAsserter

@PublishedApi
internal fun overrideAsserter(value: Asserter?): Asserter? = _asserter.also { _asserter = value }

internal fun formatResultMessage(value: Any?): String = when (value) {
    is Unit -> "but was completed successfully."
    else -> "but was completed successfully with the result: <$value>."
}

internal fun AssertionErrorWithCause(message: String?, cause: Throwable?): AssertionError =
    AssertionError(message, cause)
