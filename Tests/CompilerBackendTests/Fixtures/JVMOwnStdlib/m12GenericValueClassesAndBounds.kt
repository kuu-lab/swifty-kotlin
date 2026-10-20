@JvmInline value class Box<T>(val value: T) {
    fun get(): T = value
    fun <R> replace(other: R): Box<R> = Box(other)
}
@JvmInline value class NonNull<T: Any>(val value: T)
@JvmInline value class Numeric<T: Number>(val value: T)
@JvmInline value class Text<T: String>(val value: T)
fun echo(v: Box<Int>): Box<Int> = v
fun optional(v: Box<Int>?): Box<Int>? = v
fun nonNull(v: NonNull<String>?): NonNull<String>? = v
fun number(v: Numeric<Int>?): Numeric<Int>? = v
fun text(v: Text<String>?): Text<String>? = v
fun <T> identity(v: Box<T>): Box<T> = v
fun main() {
    val box = Box(21)
    println(echo(box).value); println(box.get()); println(box.replace("text"))
    println(Box<String?>(null)); println(optional(null)); println(optional(box))
    println(nonNull(null)); println(nonNull(NonNull("nonnull")))
    println(number(null)); println(number(Numeric(42)))
    println(text(null)); println(text(Text("bounded")))
    val any: Any = box; println(any); println(any == Box(21)); println(box.hashCode())
    val list = listOf(box); println(list[0].value); println(identity(Box(9L)).value)
    val array = Box(intArrayOf(4, 5)); val raw: IntArray = array.value; println(raw[1])
    val read = { box.value }; println(read())
}
