// Regression for BUG-171: bare (implicit-receiver) member calls inside
// String extension functions must resolve the same as explicit `this.` calls.

fun String.trimmedBeforeFirst(c: Char): String {
    val i = indexOf(c)
    return if (i < 0) this else substring(0, i)
}

fun String.trimmedAfterLast(c: Char): String {
    val i = lastIndexOf(c)
    return if (i < 0) this else substring(i + 1)
}

fun String.repeatedParts(): String {
    val parts = split(" ")
    return parts[0] + parts[1]
}

fun main() {
    println("hello world".trimmedBeforeFirst(' '))
    println("hello world".trimmedAfterLast(' '))
    println("ab cd".repeatedParts())
}
