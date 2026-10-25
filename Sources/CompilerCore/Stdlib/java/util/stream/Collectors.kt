package java.util.stream

import java.util.function.BiConsumer
import java.util.function.Function
import java.util.function.Supplier

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
}
