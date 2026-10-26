import java.util.Arrays
import java.util.Objects
import java.util.OptionalDouble
import java.util.OptionalInt
import java.util.OptionalLong
import java.util.function.BiConsumer
import java.util.function.BiFunction
import java.util.function.Consumer
import java.util.function.Function
import java.util.function.Predicate
import java.util.function.Supplier
import java.util.function.UnaryOperator
import java.util.stream.Collectors
import java.util.stream.IntStream
import java.util.stream.Stream

fun main() {
    val function = Function<Int, Int> { it * 2 }
    val predicate = Predicate<Int> { it > 0 }
    val supplier = Supplier<Int> { 7 }
    val biFunction = BiFunction<Int, Int, Int> { first, second -> first + second }
    val biConsumer = BiConsumer<String, Int> { label, value -> println("$label:$value") }
    val consumer = Consumer<Int> { }

    println(function.apply(3))
    println(predicate.test(1))
    println(supplier.get())
    println(biFunction.apply(2, 4))
    biConsumer.accept("pair", 9)
    consumer.accept(0)

    println(Stream.of(1, 2, 3).filter(Predicate<Int> { it > 1 }).count())
    println(Stream.of(1, 2, 3).map(Function<Int, Int> { it * 2 }).collect(Collectors.toList()).joinToString(","))
    println(IntStream.of(1, 2, 3).sum())
    println(IntStream.range(1, 4).sum())
    println(Arrays.stream(intArrayOf(1, 2, 3)).sum())
    println(Arrays.stream(intArrayOf(1, 2, 3, 4), 1, 3).sum())
    println(listOf(1, 2, 3).stream().map(Function<Int, Int> { it + 1 }).collect(Collectors.toList()).joinToString(","))

    val values = mutableListOf(1, 2, 3)
    values.replaceAll(UnaryOperator<Int> { it * 2 })
    println(values.joinToString(","))
    println(Objects.requireNonNull("value") { "missing" })

    println(OptionalInt.of(5).orElse(0))
    println(OptionalInt.empty().orElse(9))
    println(OptionalInt.of(5).stream().sum())
    println(OptionalLong.of(8L).orElse(0L))
    println(OptionalDouble.of(2.5).orElse(0.0))
}
