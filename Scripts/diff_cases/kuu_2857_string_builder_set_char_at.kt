// DIFF_JVM
// KUU-2857: StringBuilder JVM declarations expose setCharAt alongside existing mutations.
fun main() {
    val sb = StringBuilder("abc")
    sb.setCharAt(0, 'z')
    println(sb)
    sb.setLength(2)
    println(sb.substring(0, 2))
    sb.deleteRange(0, 1)
    println(sb)
}
