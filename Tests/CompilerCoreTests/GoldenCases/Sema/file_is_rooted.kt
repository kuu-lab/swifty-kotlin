import java.io.File

fun main() {
    val f = File("/tmp/golden_isrooted.txt")
    println(f.isRooted)
}
