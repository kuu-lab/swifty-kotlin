import java.io.*

fun main() {
    val output = ByteArrayOutputStream()
    PrintStream(output).print("x")
    println(output.toString())
}
