private fun checkRange(text: String, start: Int, end: Int) {
    try {
        println(text.toCharArray(start, end).contentToString())
    } catch (e: IndexOutOfBoundsException) {
        println("IndexOutOfBoundsException")
    } catch (e: IllegalArgumentException) {
        println("IllegalArgumentException")
    }
}

fun main() {
    val text = "abcdef"
    println(text.toCharArray(1, 4).contentToString())
    println(text.toCharArray().contentToString())
    println(text.toCharArray(2).contentToString())
    println(text.toCharArray(endIndex = 3).contentToString())
    println(text.toCharArray(endIndex = 4, startIndex = 1).contentToString())
    val sequence: CharSequence = text
    println(sequence.toCharArray().contentToString())
    checkRange(text, 0, text.length)
    checkRange(text, 0, 0)
    checkRange(text, text.length, text.length)
    checkRange("", 0, 0)
    checkRange(text, -1, 3)
    checkRange(text, 0, 7)
    checkRange(text, 4, 2)
    checkRange(text, 0, -1)
    checkRange(text, 7, 6)
    checkRange(text, -1, -1)
    checkRange(text, 7, 7)
    checkRange(text, 5, 7)
    checkRange(text, -1, -2)
    val unicode = "A\uD83D\uDE00\u00E9Z"
    val middle = unicode.toCharArray(1, 4)
    println(middle.size)
    println(middle[0].code)
    println(middle[1].code)
    println(middle[2].code)
    println(unicode.toCharArray(1, 2)[0].code)
    println(unicode.toCharArray(2, 3)[0].code)
}
