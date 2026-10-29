// KUU-3731: overriding a generic vararg member must emit an erased JVM bridge,
// and call sites must allocate the specialized array component type.
interface GenericVararg<T> { fun join(vararg values: T): String }
class Words : GenericVararg<String> {
    override fun join(vararg values: String): String =
        if (values.isEmpty()) "empty" else values[0] + values[1]
}
interface PlainVararg { fun join(vararg values: String): String }
class PlainWords : PlainVararg {
    override fun join(vararg values: String): String = values[0] + values[1]
}
open class GenericBase<T> { open fun pick(vararg values: T): String = values[0].toString() }
class Tags : GenericBase<String>() {
    override fun pick(vararg values: String): String = values[1] + values[0]
}
fun <R> top(vararg values: R): String = values.size.toString() + ":" + values[0].toString()
fun main() {
    val words: GenericVararg<String> = Words()
    println(words.join("a", "b"))
    println(words.join())
    val direct = Words()
    println(direct.join("c", "d"))
    val plain: PlainVararg = PlainWords()
    println(plain.join("x", "y"))
    val arr = arrayOf("s", "p")
    println(words.join(*arr))
    val tags: GenericBase<String> = Tags()
    println(tags.pick("m", "n"))
    println(top("a", "b"))
    println(top(1, 2))
    println(top("a", 1))
}
