fun main() {
    val chars = charArrayOf('a', 'b', 'c')
    val anyValue: Any? = null
    val byteValue: Byte = 1
    val shortValue: Short = 2
    val appended = StringBuilder()
    appended.append(anyValue).append(byteValue).append(chars).append(shortValue)
    appended.appendRange(chars, 1, 3)
    println(appended.toString())

    val indexed = StringBuilder("a😀ba😀b")
    println("${indexed.indexOf("😀")},${indexed.indexOf("😀", 4)}")
    println("${indexed.lastIndexOf("b")},${indexed.lastIndexOf("b", 4)}")

    val sequence: CharSequence? = null
    println(StringBuilder("ab").insert(1, byteValue).toString())
    println(StringBuilder("ab").insert(1, chars).toString())
    println(StringBuilder("ab").insert(1, sequence).toString())
    println(StringBuilder("ab").insert(1, shortValue).toString())
    println(StringBuilder("ab").insertRange(1, chars, 1, 3).toString())

    val aliased = StringBuilder("ab")
    aliased.insert(1, aliased)
    println(aliased.toString())

    val aliasedAtZero = StringBuilder("ab")
    aliasedAtZero.insert(0, aliasedAtZero)
    println(aliasedAtZero.toString())

    val aliasedAtEnd = StringBuilder("ab")
    aliasedAtEnd.insert(2, aliasedAtEnd)
    println(aliasedAtEnd.toString())

    val aliasedLongAtZero = StringBuilder("abc")
    aliasedLongAtZero.insert(0, aliasedLongAtZero)
    println(aliasedLongAtZero.toString())

    val aliasedLongAtOne = StringBuilder("abc")
    aliasedLongAtOne.insert(1, aliasedLongAtOne)
    println(aliasedLongAtOne.toString())

    val aliasedLongAtEnd = StringBuilder("abc")
    aliasedLongAtEnd.insert(3, aliasedLongAtEnd)
    println(aliasedLongAtEnd.toString())

    val shortened = StringBuilder("abc")
    shortened.setLength(1)
    println(shortened.toString())

    try {
        StringBuilder("abc").setLength(-1)
        println("setLength-missed")
    } catch (_: IndexOutOfBoundsException) {
        println("setLength-oob")
    }

    val substring = StringBuilder("a😀b")
    println(substring.substring(1))
    println(substring.substring(1, 3))

    try {
        substring.substring(0, 4)
        println("substring-missed")
    } catch (_: IndexOutOfBoundsException) {
        println("substring-oob")
    }

    val destination = CharArray(4)
    StringBuilder("wxyz").toCharArray(destination, 1, 1, 3)
    println("${destination[1]}${destination[2]}")

    try {
        StringBuilder("wxyz").toCharArray(destination, 3, 0, 2)
        println("toCharArray-missed")
    } catch (_: IndexOutOfBoundsException) {
        println("toCharArray-oob")
    }

    val defaultDestination = CharArray(2)
    StringBuilder("xy").toCharArray(defaultDestination)
    println("${defaultDestination[0]}${defaultDestination[1]}")
}
