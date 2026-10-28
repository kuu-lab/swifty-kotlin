import java.util.stream.IntStream

fun main() {
    println(IntStream.of(Int.MAX_VALUE, Int.MAX_VALUE).average().getAsDouble())
    println(IntStream.of(Int.MAX_VALUE, Int.MAX_VALUE).sum())
    println(IntStream.of(Int.MIN_VALUE, Int.MIN_VALUE).average().getAsDouble())
    println(IntStream.of(Int.MAX_VALUE, Int.MIN_VALUE).average().getAsDouble())
    println(IntStream.of(Int.MAX_VALUE).average().getAsDouble())
    println(IntStream.empty().average().orElse(-1.0))
    println(IntStream.of(1, 2, 3).average().getAsDouble())
    println(IntStream.of(1, 2, 3).sum())
}
