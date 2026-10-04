fun main() {
    println(('e' downTo 'a').joinToString(""))
    println(('g' downTo 'a' step 2).joinToString("-"))

    val progression: CharProgression = 'f' downTo 'a' step 2
    println(progression.joinToString(prefix = "[", postfix = "]"))
    println(progression.joinToString("|") { it.toString() })
}
