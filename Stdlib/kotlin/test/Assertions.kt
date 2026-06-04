package kotlin.test

fun assertEquals(expected: Any?, actualValue: Any?): Unit {
    if (expected != actualValue) {
        throw AssertionError("Expected <$expected>, actual <$actualValue>")
    }
}

fun assertEquals(expected: Any?, actualValue: Any?, message: Any?): Unit {
    if (expected != actualValue) {
        throw AssertionError("$message: Expected <$expected>, actual <$actualValue>")
    }
}

fun assertTrue(actualValue: Boolean): Unit {
    if (!actualValue) {
        throw AssertionError("Expected true, but was false")
    }
}

fun assertTrue(actualValue: Boolean, message: Any?): Unit {
    if (!actualValue) {
        throw AssertionError("$message: Expected true, but was false")
    }
}

fun assertNull(actualValue: Any?): Unit {
    if (actualValue != null) {
        throw AssertionError("Expected null, but was <$actualValue>")
    }
}

fun assertNull(actualValue: Any?, message: Any?): Unit {
    if (actualValue != null) {
        throw AssertionError("$message: Expected null, but was <$actualValue>")
    }
}
