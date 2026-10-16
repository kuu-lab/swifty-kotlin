@file:OptIn(kotlin.test.ExperimentalKotlinTestApi::class)
import kotlin.test.*

fun nullableValue(): String? = "present"

fun main() {

    assertNull(null)
    val value = nullableValue()
    val result: String = assertNotNull(value)
    println(result)
    println(value.length)
    try { assertNull("value") } catch (e: AssertionError) { println(e.message) }
    try { assertNotNull<String>(null, "custom") } catch (e: AssertionError) { println(e.message) }
    try { assertNull(1, "") } catch (e: AssertionError) { println(e.message) }

    var lazyCalls = 0
    assertNull(null) { lazyCalls++; "unused null message" }
    println(lazyCalls)
    try { assertNull("value") { lazyCalls++; "lazy null message" } } catch (e: AssertionError) { println(e.message) }
    println(lazyCalls)

    var blockCalls = 0
    assertNotNull("block", "deprecated") { value -> blockCalls++; println(value) }
    println(blockCalls)
    try { assertNotNull(null as String?, "deprecated failure") { blockCalls++ } } catch (e: AssertionError) { println(e.message) }
    println(blockCalls)
}
