import java.util.stream.*

// KUU-4066: a zero-argument generic factory whose type parameter occurs only
// in its return type must infer `T` from the concrete positions of
// `collect`'s `Collector<T, A, R>` parameter after the residual outer
// function type parameters (`A`, `R`) are erased to `*`.
fun main() {
    val count: Long = Stream.of("a", "b", "c").collect(Collectors.counting())
    println(count)
    val set: Set<String> = Stream.of("a", "a", "b").collect(Collectors.toSet())
    println(set.size)
    println(set.contains("a"))
    println(Stream.of("x", "y").collect(Collectors.counting()))
}
