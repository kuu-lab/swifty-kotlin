/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test <libraries/kotlin.test/common/src/main/kotlin/kotlin/test/Assertions.kt> (Kotlin 2.3.10).
 */

package kotlin.test

import kotlin.native.concurrent.ThreadLocal

/** Current adapter providing assertion implementations. */
public val asserter: Asserter
    get() = _asserter ?: lookupAsserter()

/** Used to override the current asserter internally. */
@ThreadLocal
internal var _asserter: Asserter? = null

/** Abstracts the logic for performing assertions. */
public interface Asserter {
    /** Fails the current test with the specified message. */
    public fun fail(message: String?): Nothing

    /** Fails the current test with the specified message and cause exception. */
    @SinceKotlin("1.4")
    public fun fail(message: String?, cause: Throwable?): Nothing

    /** Evaluates the failure message only when [actual] is false. */
    public fun assertTrue(lazyMessage: () -> String?, actual: Boolean): Unit {
        if (!actual) {
            fail(lazyMessage())
        }
    }

    public fun assertTrue(message: String?, actual: Boolean): Unit {
        assertTrue({ message }, actual)
    }

    public fun assertEquals(message: String?, expected: Any?, actual: Any?): Unit {
        assertTrue({ messagePrefix(message) + "Expected <$expected>, actual <$actual>." }, actual == expected)
    }

    public fun assertNotEquals(message: String?, illegal: Any?, actual: Any?): Unit {
        assertTrue({ messagePrefix(message) + "Illegal value: <$actual>." }, actual != illegal)
    }

    public fun assertSame(message: String?, expected: Any?, actual: Any?): Unit {
        assertTrue({ messagePrefix(message) + "Expected <$expected>, actual <$actual> is not same." }, actual === expected)
    }

    public fun assertNotSame(message: String?, illegal: Any?, actual: Any?): Unit {
        assertTrue({ messagePrefix(message) + "Expected not same as <$actual>." }, actual !== illegal)
    }

    public fun assertNull(message: String?, actual: Any?): Unit {
        assertTrue({ messagePrefix(message) + "Expected value to be null, but was: <$actual>." }, actual == null)
    }

    public fun assertNotNull(message: String?, actual: Any?): Unit {
        assertTrue({ messagePrefix(message) + "Expected value to be not null." }, actual != null)
    }
}

/** Provides an asserter when it is applicable to the current context. */
public interface AsserterContributor {
    public fun contribute(): Asserter?
}
