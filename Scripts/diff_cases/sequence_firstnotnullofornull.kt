fun main() {
    val seq = sequenceOf("one", "two", "three")

    val firstHit = seq.firstNotNullOfOrNull { if (it == "three") it else null } ?: "missing"
    println(firstHit)

    val missing = sequenceOf("a", "b").firstNotNullOfOrNull<String, String> { null } ?: "missing"
    println(missing)
}
