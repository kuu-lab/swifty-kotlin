fun main() {
    // KUU-3978: a range/progression receiver is a valid Iterable source for
    // the generic zipWithNext/zip/chunked/windowed bridges.
    println((1..5).zipWithNext())
    println((1..4).zipWithNext { a, b -> a + b })
    println((4 downTo 1).zipWithNext())
    println((1..9 step 3).zipWithNext())
    println((1 until 5).zipWithNext())
    println(('a'..'d').zipWithNext())
    println((1L..4L).zipWithNext())
    println((5..5).zipWithNext())
    println((3..0).zipWithNext())
    println((1..3).zip(listOf("a", "b")))
    println((1..6).chunked(2))
    println((1..5).windowed(3, 2))
}
