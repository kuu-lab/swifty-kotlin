// KUU-3449: `Closeable { }` SAM factory. On the JVM `Closeable` is
// `java.io.Closeable` (a Java SAM interface); `kotlin.io.Closeable` does
// not exist there, so the import is required for kotlinc. KSwiftK models
// the same surface with the `kotlin.io.Closeable`/`java.io.Closeable`
// external factories backed by `__kk_closeable_create`.
import java.io.Closeable

fun main() {
    val c = Closeable { println("sam closed") }
    c.close()

    Closeable { println("use closed") }.use {
        println("inside use")
    }

    java.io.Closeable { println("qualified closed") }.close()
}
