@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
import kotlin.test.*

fun supplied(): Any? = "hello"
fun main() {
    val value = supplied()
    val result: String = assertIs<String>(value)
    println("is:$result:${value.length}")
    println("nullable:${assertIs<String?>(null)}")
    assertIs<List<String>>(listOf(1))
    assertIsNot<Int>(value)
    assertIsNot<String>(null)
    println("erased-and-not")
    try { assertIs<Int>(value, "custom") } catch (e: AssertionError) { println(e.message?.startsWith("custom. Expected value to be of type <")) }
    try { assertIsNot<String>(value, "custom") } catch (e: AssertionError) { println(e.message?.startsWith("custom. Expected value to not be of type <")) }
    try { assertIsNot<String?>(null) } catch (e: AssertionError) { println(e.message?.startsWith("Expected value to not be of type <")) }
}
