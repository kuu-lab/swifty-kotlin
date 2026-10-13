@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)
import kotlin.test.*

fun main() {
    assertEquals(1.0, 1.25, 0.25)
    assertEquals(Double.NaN, Double.NaN, 0.0)
    assertEquals(Double.POSITIVE_INFINITY, Double.POSITIVE_INFINITY, 0.0)
    assertEquals(0.0, -0.0, -0.0)
    assertEquals(1.0, 99.0, Double.POSITIVE_INFINITY)
    assertNotEquals(1.0, 1.5, 0.25)
    assertNotEquals(Double.NaN, 1.0, Double.POSITIVE_INFINITY)
    assertNotEquals(Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 0.0)
    try { assertEquals(1.0, 1.5, 0.25, "Double") } catch (e: AssertionError) { println(e.message) }
    try { assertNotEquals(1.0, 1.25, 0.25) } catch (e: AssertionError) { println(e.message) }
    try { assertEquals(1.0, 1.0, -1.0) } catch (e: IllegalArgumentException) { println(e.message) }
    try { assertNotEquals(1.0, 2.0, Double.NaN) } catch (e: IllegalArgumentException) { println(e.message) }
    assertEquals(1.0f, 1.25f, 0.25f)
    assertEquals(Float.NaN, Float.NaN, 0.0f)
    assertEquals(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, 0.0f)
    assertEquals(0.0f, -0.0f, -0.0f)
    assertEquals(1.0f, 99.0f, Float.POSITIVE_INFINITY)
    assertNotEquals(1.0f, 1.5f, 0.25f)
    assertNotEquals(Float.NaN, 1.0f, Float.POSITIVE_INFINITY)
    assertNotEquals(Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, 0.0f)
    try { assertEquals(1.0f, 1.5f, 0.25f, "Float") } catch (e: AssertionError) { println(e.message) }
    try { assertNotEquals(1.0f, 1.25f, 0.25f) } catch (e: AssertionError) { println(e.message) }
    try { assertEquals(1.0f, 1.0f, -1.0f) } catch (e: IllegalArgumentException) { println(e.message) }
    try { assertNotEquals(1.0f, 2.0f, Float.NaN) } catch (e: IllegalArgumentException) { println(e.message) }
}
