class Number(val n: Int) {
    operator fun plus(x: Int): Number = Number(n + x)
    operator fun inc(): Number = Number(n + 1)
    fun copy(): Number? {
        val result: Number? = Number(n)
        return result
    }
}

fun <Number> identity(value: Number): Number = value
fun builtinNumber(value: kotlin.Number): Int = value.toInt()
fun numberValue(value: Any): Int = if (value is Number) value.n else -1

fun main() {
    var n = Number(10)
    n += 5
    n++
    println(n.n)
    println(n.copy()?.n)
    println(identity(n).n)
    println(builtinNumber(7))
    println(numberValue(n))
    println(numberValue(7))
}
