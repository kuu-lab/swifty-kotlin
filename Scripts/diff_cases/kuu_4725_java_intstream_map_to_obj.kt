// DIFF_JVM
import java.util.function.Consumer
import java.util.stream.IntStream

fun main() {
    IntStream.range(1, 4)
        .mapToObj { it * 2 }
        .forEach(Consumer<Int> { println(it) })
}
