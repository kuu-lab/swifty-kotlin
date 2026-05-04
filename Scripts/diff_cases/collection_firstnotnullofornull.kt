fun main() {
    val items: Iterable<String> = listOf("one", "two", "three")

    val firstHit = items.firstNotNullOfOrNull { if (it == "two") it else null } ?: "missing"
    println(firstHit)

    val missing = items.firstNotNullOfOrNull<String, String> { null } ?: "missing"
    println(missing)
}
