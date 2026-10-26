// DIFF_JVM: KUU-3473 checks Java CharSequence streams and StringBuilder code-point methods.
fun main() {
    println("ab".chars().count())
    println("ab".codePoints().sum())

    val sequence: CharSequence = "A\uD83D\uDE00B"
    println(sequence.chars().count())
    println(sequence.codePoints().count())
    println(sequence.codePoints().sum())

    val builder = StringBuilder("A\uD83D\uDE00B")
    println(builder.codePointAt(1))
    println(builder.codePointBefore(3))
    println(builder.codePointCount(0, builder.length))
    println(builder.codePointCount(1, 3))
}
