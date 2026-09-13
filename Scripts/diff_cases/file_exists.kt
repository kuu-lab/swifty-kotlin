// DIFF_LINE_PATTERN: kswiftk_exists_[0-9]+
import java.io.File

fun main() {
    val base = "/tmp/kswiftk_exists_" + System.currentTimeMillis()
    val dir = File(base)
    val file = File(base + "/test.txt")

    // name and path properties
    println(dir.name)             // "kswiftk_exists_<timestamp>"
    println(dir.path)             // "/tmp/kswiftk_exists_<timestamp>"
    println(file.name)            // "test.txt"
    println(file.path)            // "/tmp/kswiftk_exists_<timestamp>/test.txt"

    // Verify name and path work correctly
    println(file.name.equals("test.txt"))     // true
    println(dir.name.startsWith("kswiftk_exists_"))  // true
    println(file.path.endsWith("/test.txt"))  // true
}
