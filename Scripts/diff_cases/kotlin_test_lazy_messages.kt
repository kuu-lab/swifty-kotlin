// DIFF_CANDIDATE_ONLY: Experimental lazy-message APIs are marked SinceKotlin("2.4"); the reference compiler targets Kotlin 2.3.10.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kotlin_test_lazy_messages.expected
// Reference: JetBrains/kotlin revision 150f34458460c5d688ba80e13f269ca6715f32b4, kotlin.test/common Assertions.kt.
@file:OptIn(kotlin.test.ExperimentalKotlinTestApi::class)
import kotlin.test.*

class LazyToken { override fun toString(): String = "token" }

fun lazyTrue() {
    val value = LazyToken()
    var calls = 0
    assertTrue(true) { calls++; "lazy" }
    println(calls)
    try { assertTrue(false) { calls++; "lazy" } } catch (e: AssertionError) { println(e.message) }
    println(calls)
}

fun lazyFalse() {
    val value = LazyToken()
    var calls = 0
    assertFalse(false) { calls++; "lazy" }
    println(calls)
    try { assertFalse(true) { calls++; "lazy" } } catch (e: AssertionError) { println(e.message) }
    println(calls)
}

fun lazyEquals() {
    val value = LazyToken()
    var calls = 0
    assertEquals(1, 1) { calls++; "lazy" }
    println(calls)
    try { assertEquals(1, 2) { calls++; "lazy" } } catch (e: AssertionError) { println(e.message) }
    println(calls)
}

fun lazyNotEquals() {
    val value = LazyToken()
    var calls = 0
    assertNotEquals(1, 2) { calls++; "lazy" }
    println(calls)
    try { assertNotEquals(1, 1) { calls++; "lazy" } } catch (e: AssertionError) { println(e.message) }
    println(calls)
}

fun lazyIdentity() {
    val value = LazyToken()
    var calls = 0
    assertSame(value, value) { calls++; "lazy" }; assertNotSame(value, Any()) { calls++; "lazy" }
    println(calls)
    try { assertNotSame(value, value) { calls++; "lazy" } } catch (e: AssertionError) { println(e.message) }
    println(calls)
    try { assertSame(value, LazyToken()) { calls++; "same lazy" } } catch (e: AssertionError) { println(e.message) }
    println(calls)
}

fun main() {
    lazyTrue()
    lazyFalse()
    lazyEquals()
    lazyNotEquals()
    lazyIdentity()
}
