// DIFF_JVM
import java.util.function.Consumer
import java.util.function.IntFunction
import java.util.stream.IntStream

fun main() {
    IntStream.range(1, 4)
        .mapToObj(IntFunction<String> { "value$it" })
        .forEach(Consumer<String> { println(it) })
}
