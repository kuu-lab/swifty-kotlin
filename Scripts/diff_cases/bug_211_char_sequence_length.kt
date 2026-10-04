// BUG-211: interface-typed CharSequence length must use the receiver's
// runtime representation in direct, extension, and bundled-source paths.
fun f(cs: CharSequence): Int = cs.length

fun CharSequence.lengthViaExtension(): Int = this.length

class CustomSequence(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)
}

fun main() {
    println(f("hello"))
    println("world".lengthViaExtension())
    println("abc".map { it })
    println(StringBuilder("xyz").map { it })
    println(CustomSequence("custom").length)
    println(f(CustomSequence("custom")))
    println(CustomSequence("custom").lengthViaExtension())
}
