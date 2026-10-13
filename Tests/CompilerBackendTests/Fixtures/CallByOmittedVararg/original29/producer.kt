import kotlin.reflect.KCallable

class IntValues(vararg values: Int) { val count = values.size }
class StringValues(vararg values: String) { val count = values.size }
class DoubleValues(vararg values: Double) { val count = values.size }
class WithDefault(val label: String = "default", vararg values: Int) { val count = values.size }
class DefaultAfter(vararg values: String, val label: String = "tail") { val count = values.size }
class WithRequired(val label: String, vararg values: Int) { val count = values.size }
class OptionalInts(vararg val values: Int = intArrayOf(9))
annotation class Tags(vararg val values: String)

fun intCount(vararg values: Int) = values.size
fun stringCount(vararg values: String) = values.size
fun doubleCount(vararg values: Double) = values.size
fun mixedCount(label: String = "function", vararg values: Int): String = label + ":" + values.size
class Counter(val base: Int) {
    fun count(vararg values: Int, shift: Int = 2): Int = base + shift + values.size
}

fun failure(call: () -> Any?): String = try {
    call()
    "OK"
} catch (failure: IllegalArgumentException) {
    "IAE"
}
