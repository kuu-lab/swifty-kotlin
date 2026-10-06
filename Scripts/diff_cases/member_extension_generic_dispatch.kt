class GenericOffset<T>(private val offset: T) {
    fun Int.getOffset(): T = offset
    fun <U> Int.withValue(value: U): T = offset
    fun run(n: Int): T = n.getOffset()
    fun generic(n: Int): T = n.withValue<String>("unused")
    fun nested(n: Int): T {
        val read = { n.getOffset() }
        return read()
    }
}

open class BaseOffset<T>(private val offset: T) {
    fun Int.getBaseOffset(): T = offset
}

class StringOffset : BaseOffset<String>("inherited") {
    fun run(n: Int): String = n.getBaseOffset()
}

fun main() {
    println(GenericOffset(9).run(2))
    println(GenericOffset("value").run(2))
    println(GenericOffset(10).generic(2))
    println(GenericOffset(11).nested(2))
    println(StringOffset().run(2))
}
