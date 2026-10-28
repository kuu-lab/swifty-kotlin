import java.util.function.Function
import java.util.function.Predicate
import java.util.stream.IntStream
import java.util.stream.Stream

private fun expectUsed(label: String, operation: () -> Unit) {
    try {
        operation()
        println("$label=reused")
    } catch (_: IllegalStateException) {
        println("$label=used")
    }
}

fun main() {
    val boxed = IntStream.of(1).boxed()
    println("boxed=${boxed.count()}")
    expectUsed("boxed-again") { boxed.count() }

    val mapped = IntStream.of(1).mapToObj { "value$it" }
    val mappedPipeline = mapped.filter(Predicate<String> { it.startsWith("value") })
        .map(Function<String, String> { "$it!" })
    println("mapToObj=${mappedPipeline.toList()}")
    expectUsed("mapToObj-source-again") { mapped.count() }
    expectUsed("mapToObj-result-again") { mappedPipeline.count() }

    val source = Stream.of(1, 2, 2, 3)
    val pipeline = source.filter(Predicate<Int> { it > 1 })
        .distinct()
        .map(Function<Int, Int> { it * 10 })
        .skip(1)
        .limit(1)
    expectUsed("intermediate-source-again") { source.count() }
    println("pipeline=${pipeline.toList()}")
    expectUsed("pipeline-again") { pipeline.count() }
}
