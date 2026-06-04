package kotlin.test

import kswiftk.internal.*

fun assertEquals(expected: Any?, actualValue: Any?): Unit = __testAssertEquals(expected, actualValue)

fun assertEquals(expected: Any?, actualValue: Any?, message: Any?): Unit =
    __testAssertEqualsMessage(expected, actualValue, message)

fun assertTrue(actualValue: Boolean): Unit = __testAssertTrue(actualValue)

fun assertTrue(actualValue: Boolean, message: Any?): Unit = __testAssertTrueMessage(actualValue, message)

fun assertNull(actualValue: Any?): Unit = __testAssertNull(actualValue)

fun assertNull(actualValue: Any?, message: Any?): Unit = __testAssertNullMessage(actualValue, message)
