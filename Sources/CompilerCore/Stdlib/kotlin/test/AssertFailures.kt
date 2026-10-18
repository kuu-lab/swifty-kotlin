/*
 * Copyright 2010-2021 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from JetBrains/kotlin revision 150f34458460c5d688ba80e13f269ca6715f32b4.
 * Stable APIs follow Kotlin 2.3.10; experimental lazy messages retain their 2.4 version marker.
 */
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
@file:OptIn(kotlin.contracts.ExperimentalContracts::class, kotlin.ExperimentalUnsignedTypes::class)
package kotlin.test

import kotlin.internal.InlineOnly
import kotlin.reflect.KClass

@InlineOnly
@JvmName("assertFailsAny")
@IgnorableReturnValue
public inline fun assertFails(block: () -> Any?): Throwable =
    checkResultIsFailure(null, runCatching(block))

@InlineOnly
@JvmName("assertFailsInline")
@Deprecated(ASSERT_FAILS_NOTE, level = DeprecationLevel.HIDDEN)
public inline fun assertFails(block: () -> Unit): Throwable =
    checkResultIsFailure(null, runCatching(block))

@SinceKotlin("1.1")
@InlineOnly
@JvmName("assertFailsAny")
@IgnorableReturnValue
public inline fun assertFails(message: String?, block: () -> Any?): Throwable =
    checkResultIsFailure(message, runCatching(block))

@SinceKotlin("1.1")
@InlineOnly
@JvmName("assertFailsInline")
@Deprecated(ASSERT_FAILS_NOTE, level = DeprecationLevel.HIDDEN)
public inline fun assertFails(message: String?, block: () -> Unit): Throwable =
    checkResultIsFailure(message, runCatching(block))

@PublishedApi
internal fun checkResultIsFailure(message: String?, blockResult: Result<Any?>): Throwable {
    blockResult.fold(
        onSuccess = { v ->
            asserter.fail(messagePrefix(message) + "Expected an exception to be thrown, ${formatResultMessage(v)}")
        },
        onFailure = { e ->
            return e
        }
    )
}

@InlineOnly
@JvmName("assertFailsWithAny")
@IgnorableReturnValue
public inline fun <reified T : Throwable> assertFailsWith(message: String? = null, block: () -> Any?): T =
    assertFailsWith(T::class, message, block)

@InlineOnly
@Deprecated(ASSERT_FAILS_NOTE, level = DeprecationLevel.HIDDEN)
public inline fun <reified T : Throwable> assertFailsWith(message: String? = null, block: () -> Unit): T =
    assertFailsWith(T::class, message, block)

@InlineOnly
@JvmName("assertFailsWithAny")
@IgnorableReturnValue
public inline fun <T : Throwable> assertFailsWith(exceptionClass: KClass<T>, block: () -> Any?): T = assertFailsWith(exceptionClass, null, block)

@InlineOnly
@JvmName("assertFailsWithInline")
@Deprecated(ASSERT_FAILS_NOTE, level = DeprecationLevel.HIDDEN)
public inline fun <T : Throwable> assertFailsWith(exceptionClass: KClass<T>, block: () -> Unit): T = assertFailsWith(exceptionClass, null, block)

@InlineOnly
@JvmName("assertFailsWithAny")
@IgnorableReturnValue
public inline fun <T : Throwable> assertFailsWith(exceptionClass: KClass<T>, message: String?, block: () -> Any?): T =
    checkResultIsFailure(exceptionClass, message, runCatching(block))

@InlineOnly
@JvmName("assertFailsWithInline")
@Deprecated(ASSERT_FAILS_NOTE, level = DeprecationLevel.HIDDEN)
public inline fun <T : Throwable> assertFailsWith(exceptionClass: KClass<T>, message: String?, block: () -> Unit): T =
    checkResultIsFailure(exceptionClass, message, runCatching(block))

private const val ASSERT_FAILS_NOTE = "Provided for binary compatibility. assertFails(With) overload with () -> Any? should be used instead."

@PublishedApi
internal fun <T : Throwable> checkResultIsFailure(exceptionClass: KClass<T>, message: String?, blockResult: Result<Any?>): T {
    blockResult.fold(
            onSuccess = { v ->
                asserter.fail(messagePrefix(message) + "Expected an exception of ${exceptionClass.qualifiedName} to be thrown, ${formatResultMessage(v)}.")
            },
            onFailure = { e ->
                if (exceptionClass.isInstance(e)) {
                    @Suppress("UNCHECKED_CAST")
                    return e as T
                }
                asserter.fail(messagePrefix(message) + "Expected an exception of ${exceptionClass.qualifiedName} to be thrown, but was $e", e)
            }
    )
}
