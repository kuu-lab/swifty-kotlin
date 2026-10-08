// KUU-1637: a same-named top-level function must not hide Char::titlecase.
fun titlecase(value: String): String = value.replaceFirstChar(Char::titlecase)

fun main() {
    println(titlecase("kotlin"))
}
