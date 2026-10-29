// DIFF_JVM
private var calls = 0
private fun nextChars(): CharArray? {
    calls++
    return charArrayOf('x')
}

private class Named {
    fun concatToString(): String = "custom"
}

fun main() {
    val chars: CharArray? = charArrayOf('h', 'i')
    val missing: CharArray? = null
    println(chars?.concatToString())
    println(missing?.concatToString())
    println(charArrayOf('o', 'k').concatToString())
    val named: Named? = Named()
    val absent: Named? = null
    println(named?.concatToString())
    println(absent?.concatToString())
    println(nextChars()?.concatToString())
    println(calls)
}
