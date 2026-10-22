// DIFF_JVM
fun main() {
    val chars: CharArray? = charArrayOf('h', 'i')
    val missing: CharArray? = null
    println(chars?.concatToString())
    println(missing?.concatToString())
}
