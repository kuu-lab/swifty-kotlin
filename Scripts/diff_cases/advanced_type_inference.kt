fun <T> collect(builderAction: MutableList<T>.() -> Unit): List<T> = buildList<T>(builderAction)

fun <K, V> collectMap(builderAction: MutableMap<K, V>.() -> Unit): Map<K, V> = buildMap<K, V>(builderAction) as Map<K, V>

fun main() {
    val numbers = collect<Int> {
        add(1)
        add(2)
        add(3)
    }

    val labels = collectMap<Int, String> {
        put(1, "one")
        put(2, "two")
    }

    val generated = sequence {
        yield(numbers[0])
        for (n in numbers) {
            yield(n)
        }
    }

    println(numbers[0] + generated.first())
    println(labels[2] ?: "missing")
}
