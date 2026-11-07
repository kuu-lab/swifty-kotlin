package java.util.stream

import java.util.function.BiConsumer
import java.util.function.Function
import java.util.function.Supplier
import java.util.function.ToIntFunction

public object Collectors {
    public fun toList(): ListCollector = ListCollector()

    public fun <T> toSet(): Collector<T, MutableSet<T>, Set<T>> = Collector(
        Supplier { mutableSetOf<T>() },
        BiConsumer { values, value -> values.add(value); Unit },
        Function { values -> values },
    )

    public fun <T> counting(): Collector<T, MutableList<T>, Long> = Collector(
        Supplier { mutableListOf<T>() },
        BiConsumer { values, value -> values.add(value); Unit },
        Function { values -> values.size.toLong() },
    )

    public fun joining(
        delimiter: CharSequence = "",
        prefix: CharSequence = "",
        suffix: CharSequence = "",
    ): Collector<CharSequence, MutableList<CharSequence>, String> = Collector(
        Supplier { mutableListOf<CharSequence>() },
        BiConsumer { values, value -> values.add(value); Unit },
        Function { values -> values.joinToString(delimiter.toString(), prefix.toString(), suffix.toString()) },
    )

    public fun <T, K, V> toMap(
        keyMapper: Function<T, K>,
        valueMapper: Function<T, V>,
    ): Collector<T, MutableMap<K, V>, Map<K, V>> = Collector(
        Supplier { mutableMapOf<K, V>() },
        BiConsumer { map, value ->
            val key = keyMapper.apply(value)
            if (map.containsKey(key)) throw IllegalStateException("Duplicate key")
            map[key] = valueMapper.apply(value)
        },
        Function { it },
    )

    public fun <T, K> groupingBy(classifier: Function<T, K>): Collector<T, MutableMap<K, MutableList<T>>, Map<K, List<T>>> =
        Collector(
            Supplier { mutableMapOf<K, MutableList<T>>() },
            BiConsumer { map, value ->
                map.getOrPut(classifier.apply(value)) { mutableListOf() }.add(value)
            },
            Function { it },
        )

    public fun <T> summingInt(mapper: ToIntFunction<T>): Collector<T, IntArray, Int> = Collector(
        Supplier { intArrayOf(0) },
        BiConsumer { acc, value -> acc[0] += mapper.applyAsInt(value) },
        Function { it[0] },
    )
}
