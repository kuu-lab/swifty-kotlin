class UserSequence(private val content: String) : CharSequence {
    override val length: Int get() = content.length
    override fun get(index: Int): Char = content[index]
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)
}

fun main() {
    val string: CharSequence = "hello"
    println(string.length)
    println(string[1])
    println(string.get(2))

    val builder: CharSequence = StringBuilder("hello")
    println(builder.length)
    println(builder[3])
    println(builder.get(4))

    val unicode: CharSequence = "🥦"
    println(unicode.length)
    println(unicode[0].code)
    println(unicode[1].code)

    val unicodeBuilder: CharSequence = StringBuilder("🥦")
    println(unicodeBuilder.length)
    println(unicodeBuilder[0].code)
    println(unicodeBuilder[1].code)

    val user: CharSequence = UserSequence("world")
    println(user.length)
    println(user[1])
    println(user.get(2))

    try {
        string[5]
        println("missing-string-exception")
    } catch (e: IndexOutOfBoundsException) {
        println("string-index-out-of-bounds")
    }

    try {
        builder[-1]
        println("missing-builder-exception")
    } catch (e: IndexOutOfBoundsException) {
        println("builder-index-out-of-bounds")
    }
}
