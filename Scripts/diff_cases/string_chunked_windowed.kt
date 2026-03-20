fun main() {
    // === String.chunked(size) ===
    // Basic chunked
    println("abcdef".chunked(2))
    println("abcdefg".chunked(3))
    println("abcde".chunked(1))
    println("abcde".chunked(5))
    println("abcde".chunked(10))

    // Empty string
    println("".chunked(3))

    // Single character chunks
    println("abc".chunked(1))

    // Chunk size equals string length
    println("hello".chunked(5))

    // Chunk size greater than string length
    println("hi".chunked(100))

    // Various sizes
    println("abcdefghij".chunked(3))
    println("abcdefghij".chunked(4))

    // Verify list type behavior
    val chunks = "abcdef".chunked(2)
    println(chunks.size)
    println(chunks[0])
    println(chunks[1])
    println(chunks[2])

    // Partial last chunk
    val partial = "abcde".chunked(2)
    println(partial)
    println(partial.size)
    println(partial.last())

    // Large chunk size
    println("x".chunked(1))
    println("xy".chunked(5))

    // === String.windowed (2-arg) ===
    println("abcde".windowed(3, 1))
    println("abcde".windowed(3, 2))
    println("abcde".windowed(2, 1))
}
