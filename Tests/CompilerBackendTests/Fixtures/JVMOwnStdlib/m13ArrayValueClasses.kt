@JvmInline value class Numbers(val value: IntArray)
@JvmInline value class Optional(val value: IntArray?)
@JvmInline value class Items<T>(val value: Array<T>)
fun echo(v: Numbers): Numbers = v
fun optional(v: Numbers?): Numbers? = v
fun main() {
    val raw = intArrayOf(1, 2)
    val first = Numbers(raw); val second = Numbers(raw)
    println(echo(first)); println(first == second); println(first == Numbers(intArrayOf(1, 2)))
    println(first.hashCode()); println(optional(null)); println(optional(first))
    raw[0] = 3; println(first); println(first.hashCode())
    val none = Optional(null); println(none); println(none.hashCode()); println(none == Optional(null))
    val items = Items(arrayOf("a", "b")); val values: Array<String> = items.value
    println(items); println(values[1]); println(items.hashCode())
    val read = { first.value[0] }; println(read())
}
