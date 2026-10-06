// An implicit-receiver `toInt(radix)` / `toLong(radix)` inside a String
// extension must call String.toInt(radix), not convert the radix argument.
fun String.parseImplicit(radix: Int): Int = toInt(radix)
fun String.parseImplicitLong(radix: Int): Long = toLong(radix)
fun String.parseExplicit(radix: Int): Int = this.toInt(radix)

fun main() {
    println("ff".parseImplicit(16))
    println("ff".parseImplicitLong(16))
    println("ff".parseExplicit(16))
    println(7.toLong() + 1)
}
