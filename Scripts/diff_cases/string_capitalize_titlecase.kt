@file:Suppress("DEPRECATION")

fun main() {
    println("ǆenan".capitalize())
    println("ǉubǉana".capitalize())
    println("ǌegoš".capitalize())
    println("ǳuro".capitalize())

    // Only lowercase initials change: titlecase and uppercase forms stay intact.
    val digraphs = listOf("Ǆ", "ǅ", "ǆ", "Ǉ", "ǈ", "ǉ", "Ǌ", "ǋ", "ǌ", "Ǳ", "ǲ", "ǳ")
    for (s in digraphs) {
        println((s + "aBc").capitalize())
    }

    // JVM capitalize retains full uppercase expansions when simple titlecase
    // and uppercase agree; it is not an unconditional Char.titlecase() call.
    println("ßeta".capitalize())
    println("ﬃle".capitalize())
    println("ᾀbc".capitalize())
    println("ᾈbc".capitalize())

    println("".capitalize())
    println("hello".capitalize())
    println("Hello".capitalize())
    println("a".capitalize())
    println("1abc".capitalize())
    println("!abc".capitalize())
    println("😀abc".capitalize())
    println("e\u0301ABC".capitalize())

    println("ǅENAN".decapitalize())
    println("ǄENAN".decapitalize())
}
