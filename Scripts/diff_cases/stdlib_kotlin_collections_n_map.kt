fun singletonPair(): Pair<String?, Int?> {
    println("pair")
    return Pair<String?, Int?>(null, null)
}

fun main() {
    val singleton = mapOf(singletonPair())
    val equivalent = mapOf<String?, Int?>(Pair<String?, Int?>(null, null))

    println(singleton)
    println(singleton.size)
    println(singleton.containsKey(null))
    println(singleton[null] == null)
    println(singleton == equivalent)
    println(singleton.entries.first().key == null)
    println(singleton.entries.first().value == null)
    println(singleton.entries.map { "${it.key}:${it.value}" })
}
