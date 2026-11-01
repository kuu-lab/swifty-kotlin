// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kotlinx_io_utf8size.expected.stdout
// Candidate-only: upstream kotlinx-io 0.9.1 keeps String.utf8Size internal, so
// there is no JVM kotlinc reference for these calls. KUU-4112 exposes the
// bundled declaration as public per okio parity (`okio.Utf8.utf8Size`), and the
// expected output pins upstream's sizing rules: malformed surrogates count one
// byte ('?'), valid surrogate pairs count four, and the bounds checks come from
// kotlinx-io checkBounds (IndexOutOfBoundsException / IllegalArgumentException).
import kotlinx.io.*

// The KUU-4112 minimal repro shape: a top-level call outside the stdlib module.
val reproTopLevelUtf8Size = "abc".utf8Size()

fun main() {
    println(reproTopLevelUtf8Size)
    println("".utf8Size())
    println("é".utf8Size())
    println("€".utf8Size())
    println("日".utf8Size())
    println("😀".utf8Size())
    println("aé日😀".utf8Size())

    // Malformed UTF-16: each unpaired surrogate counts as one '?' byte.
    println("\uD800".utf8Size())
    println("\uDC00".utf8Size())
    println("a\uD800b".utf8Size())
    println("a\uDC00\uD800b".utf8Size())

    // Positional and okio-style named bounds (beginIndex/endIndex).
    println("abcdef".utf8Size(1, 4))
    println("abcdef".utf8Size(beginIndex = 1))
    println("abcdef".utf8Size(endIndex = 3))
    println("abcdef".utf8Size(beginIndex = 1, endIndex = 4))

    // A surrogate pair split by the index range is malformed at the boundary.
    println("a\uD800\uDC00z".utf8Size(1, 3))
    println("a\uD800\uDC00z".utf8Size(1, 2))
    println("a\uD800\uDC00z".utf8Size(2, 4))
    println("abc".utf8Size(3, 3))

    val typed: Long = "abc".utf8Size()
    println(typed)

    try {
        "abc".utf8Size(-1)
        println("neg:missing")
    } catch (e: IndexOutOfBoundsException) {
        println("neg:ioobe")
    }
    try {
        "abc".utf8Size(0, 4)
        println("over:missing")
    } catch (e: IndexOutOfBoundsException) {
        println("over:ioobe")
    }
    try {
        "abc".utf8Size(2, 1)
        println("reversed:missing")
    } catch (e: IllegalArgumentException) {
        println("reversed:iae")
    }
}
