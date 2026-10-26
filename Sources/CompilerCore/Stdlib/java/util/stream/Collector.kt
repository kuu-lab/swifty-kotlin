package java.util.stream

import java.util.function.BiConsumer
import java.util.function.Function
import java.util.function.Supplier

public class ListCollector internal constructor()

public class Collector<T, A, R> internal constructor(
    private val supplier: Supplier<A>,
    private val accumulator: BiConsumer<A, T>,
    private val finisher: Function<A, R>,
) {
    public fun collect(values: List<T>): R {
        val result = supplier.get()
        for (value in values) accumulator.accept(result, value)
        return finisher.apply(result)
    }
}
