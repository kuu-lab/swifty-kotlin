interface Provider {
    fun get(): Int
    companion object { fun answer(): Int = 42 }
}
open class Base(protected val n: Int) { init { println("base") }; open fun value(): Int = n }
object Answer: Base(20), Provider {
    init { println("answer") }
    override fun value(): Int = n + 22
    override fun get(): Int = value()
}
fun main() { println(Answer.get()); println(Answer.value()); println(Provider.answer()) }
