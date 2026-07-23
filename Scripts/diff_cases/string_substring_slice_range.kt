// BUG-145 regression: implicit-receiver substring must behave like explicit this.substring.
fun String.implicitSubstring(n: Int): String = substring(n)
fun String.explicitSubstring(n: Int): String = this.substring(n)

fun main() {
    // substring(startIndex)
    println("hello".substring(2))
    println("hello".substring(0))
    println("hello".substring(5) + "|")

    // substring(startIndex, endIndex)
    println("hello".substring(1, 3))
    println("hello".substring(0, 5))
    println("hello".substring(2, 2) + "|")

    // BUG-145: implicit vs explicit receiver produce identical results
    println("hello".implicitSubstring(2))
    println("hello".explicitSubstring(2))

    @Suppress("DEPRECATION")
    run {
        // subSequence delegates to substring; toString() keeps kotlinc parity
        // because the stdlib subSequence returns CharSequence (no CharSequence.plus).
        println("hello".subSequence(1, 3).toString())
        println("hello".subSequence(2, 2).toString() + "|")
    }

    // slice(IntRange)
    println("hello".slice(1..3))
    println("hello".slice(0 until 2))
    println("hello".slice(1 until 1) + "|")

    // slice(Iterable<Int>)
    println("hello".slice(listOf(0, 2, 4)))
    println("hello".slice(listOf<Int>()) + "|")

    // removeRange
    println("hello".removeRange(1, 3))
    println("hello".removeRange(1..2))
    println("hello".removeRange(2, 2))

    // replaceRange
    println("hello".replaceRange(1, 3, "XY"))
    println("hello".replaceRange(1..2, "XY"))
    println("hello".replaceRange(2, 2, "Z"))

    // empty string
    println("".substring(0) + "|")
    println("".slice(0 until 0) + "|")

    // BMP Unicode (each character is a single UTF-16 code unit)
    val u = "こんにちは"
    println(u.substring(1, 3))
    println(u.slice(1..2))
    println(u.removeRange(1, 3))
    println(u.replaceRange(1, 3, "X"))

    // invalid indices throw IndexOutOfBoundsException
    try {
        "hello".substring(-1)
    } catch (e: IndexOutOfBoundsException) {
        println("substring negative ioobe")
    }
    try {
        "hello".substring(0, 10)
    } catch (e: IndexOutOfBoundsException) {
        println("substring endGtLength ioobe")
    }
    try {
        "hello".substring(3, 1)
    } catch (e: IndexOutOfBoundsException) {
        println("substring startGtEnd ioobe")
    }
    try {
        "hello".slice(listOf(0, 9))
    } catch (e: IndexOutOfBoundsException) {
        println("slice index ioobe")
    }

    // chaining
    println("hello world".substring(0, 5).slice(1..3))
    println("hello world".substring(6).removeRange(0, 2))
}
