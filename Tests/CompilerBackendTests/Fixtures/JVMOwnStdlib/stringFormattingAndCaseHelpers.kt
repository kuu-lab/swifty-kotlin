fun main() {
    println("%d-%s".format(5, "x"))
    println("%,.1f".format(java.util.Locale.US, 1234.5))
    println("hello".capitalize())
    println("hello".replaceFirstChar { it.uppercaseChar() })
    println("hello".replaceFirstChar { "H" })
    var calls = 0
    println("".replaceFirstChar { calls++; it.uppercaseChar() }.isEmpty())
    println(calls)
}
