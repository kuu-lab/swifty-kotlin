// DIFF_JVM
interface Handler<T> {
    fun call(vararg values: Int): T
    fun callPlain(value: Int): T
}

class UnitHandler : Handler<Unit> {
    override fun call(vararg values: Int) { println("unit=" + (values[0] + values[1])) }
    override fun callPlain(value: Int) { println("plain=$value") }
}

class TextHandler : Handler<String> {
    override fun call(vararg values: Int): String = "text=" + (values[0] + values[1])
    override fun callPlain(value: Int): String = "text=$value"
}

fun main() {
    val unit: Handler<Unit> = UnitHandler()
    println("array-unit=" + (unit.call(2, 3) === Unit))
    println("plain-unit=" + (unit.callPlain(4) === Unit))
    val text: Handler<String> = TextHandler()
    println(text.call(2, 3))
    println(text.callPlain(4))
}
