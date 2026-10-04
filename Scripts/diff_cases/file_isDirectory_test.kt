import java.io.File

fun main() {
    // File name/path properties
    val f = File("/tmp/test.txt")
    println(f.name)     // "test.txt"
    println(f.path)     // "/tmp/test.txt"
}
