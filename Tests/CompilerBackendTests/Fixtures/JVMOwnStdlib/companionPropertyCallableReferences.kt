import kotlin.reflect.KProperty0
import kotlin.reflect.KProperty1

class Sample {
    companion object {
        const val maxValue = 1
        val ordinary = 2
    }
}

class Holder(val value: Int)

fun take(property: KProperty0<Int>): Int = property.get()
fun takeInstance(property: KProperty1<Holder, Int>): Int = property.get(Holder(1))

abstract class Checker {
    fun check(): String = run(Sample::maxValue, { value -> value == 1 })
    abstract fun <T1> run(method: KProperty0<T1>, fn: (T1) -> Boolean): String
}

fun box(): String {
    val original = object : Checker() {
        override fun <T1> run(method: KProperty0<T1>, fn: (T1) -> Boolean): String =
            if (fn(method.get())) "OK" else "FAIL"
    }.check()
    val minimal = take(Sample::maxValue)
    val direct = Sample.maxValue + Sample.ordinary
    val instance = takeInstance(Holder::value)
    return if (original == "OK" && minimal == 1 && direct == 3 && instance == 1) "OK" else "FAIL"
}

fun main() {
    println(box())
}
