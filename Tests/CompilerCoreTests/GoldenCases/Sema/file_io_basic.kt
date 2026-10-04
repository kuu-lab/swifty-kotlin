import java.io.File

fun main() {
    val f = File("test.txt")
    val lines = f.readLines()
    println(lines.size)
}
