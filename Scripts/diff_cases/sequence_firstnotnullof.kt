fun main() {
    val seq = sequenceOf("one", "two", "three")

    val firstHit = seq.firstNotNullOf { if (it == "three") it else null }
    println(firstHit)

    val missing = try {
        sequenceOf("a", "b").firstNotNullOf<String, String> { null }
    } catch (e: NoSuchElementException) {
        "missing"
    }
    println(missing)
}
