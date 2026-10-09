/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test <libraries/kotlin.test/common/src/main/kotlin/kotlin/test/DefaultAsserter.kt> (Kotlin 2.3.10).
 */

package kotlin.test

/** Default assertion implementation without a dependency on a test framework. */
public object DefaultAsserter : Asserter {
    override fun fail(message: String?): Nothing {
        if (message == null)
            throw AssertionError()
        else
            throw AssertionError(message)
    }

    @SinceKotlin("1.4")
    override fun fail(message: String?, cause: Throwable?): Nothing {
        throw AssertionErrorWithCause(message, cause)
    }
}
