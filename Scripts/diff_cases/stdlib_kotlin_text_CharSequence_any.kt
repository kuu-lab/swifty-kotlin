class CustomCharSequence(private val value: String) : CharSequence {
    override val length: Int get() = value.length
    override fun get(index: Int): Char = value[index]
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        return value.substring(startIndex, endIndex)
    }
}

fun main() {
    println("".any())
    println("abc".any())

    val emptyString: CharSequence = ""
    val nonEmptyString: CharSequence = "abc"
    println(emptyString.any())
    println(nonEmptyString.any())

    val emptyCustom: CharSequence = CustomCharSequence("")
    val nonEmptyCustom: CharSequence = CustomCharSequence("x")
    println(emptyCustom.any())
    println(nonEmptyCustom.any())
}
