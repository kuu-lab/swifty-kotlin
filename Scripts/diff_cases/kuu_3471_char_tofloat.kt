// KUU-3471: Char.toFloat() converts the UTF-16 code unit to Float like the
// other deprecated Char numeric conversions.
fun main() {
    println('a'.toFloat())
    println('A'.toFloat())
    println('0'.toFloat())
    println('z'.toFloat())
    println('\u0000'.toFloat())
    println('\uFFFF'.toFloat())
    println('\uD800'.toFloat())
    println(Char.MIN_VALUE.toFloat())
    println(Char.MAX_VALUE.toFloat())
}
