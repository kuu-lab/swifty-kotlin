// KSP-409: String collection conversions and iterator helpers are bundled Kotlin source.
fun main() {
    val text = "caba"
    println(text.toList().size)
    println(text.toMutableList().size)
    println(text.toCharArray().size)

    val destination = mutableListOf<Char>('!')
    text.toCollection(destination)
    println(destination.size)
    println(text.toSortedSet().size)

    var iterated = ""
    for (character in text) iterated += character
    println(iterated)

    println(text.asIterable().toList().size)
    println(text.asSequence().toList().size)
    println(text.withIndex().toList().size)

    println("".toMutableList().size)
}
