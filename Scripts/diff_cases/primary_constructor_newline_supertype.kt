// KUU-2009: Keep a next-line inheritance colon attached to the implicit primary constructor.
class ParseException(val value: Int)
    : Exception("parse")
fun main() {
    try { throw ParseException(7) } catch (e: ParseException) { println(e.value) }
}
