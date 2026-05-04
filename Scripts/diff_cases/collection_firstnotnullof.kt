fun main() {
    val items: Iterable<String> = listOf("one", "two", "three")

    val firstUpper = items.firstNotNullOf { if (it == "two") it else null }
    println(firstUpper)

    val missing = try {
        items.firstNotNullOf<String, String> { null }
    } catch (e: NoSuchElementException) {
        "missing"
    }
    println(missing)
}
