// KUU-4162: after System.in.close(), kotlin.io.readLine/readln/readlnOrNull
// and System.in.read() must throw java.io.IOException("Stream closed") like
// the JVM instead of returning null / a stale value.
// DIFF_STDIN_EOF
import java.io.IOException

fun main() {
    println("before")
    System.`in`.close()
    try {
        val line = readLine()
        println("readLine:$line")
    } catch (e: IOException) {
        println("readLine-io:${e.message}")
    }
    try {
        val value = System.`in`.read()
        println("read:$value")
    } catch (e: IOException) {
        println("read-io:${e.message}")
    }
    try {
        val line = readln()
        println("readln:$line")
    } catch (e: IOException) {
        println("readln-io:${e.message}")
    }
    try {
        val line = readlnOrNull()
        println("readlnOrNull:$line")
    } catch (e: IOException) {
        println("readlnOrNull-io:${e.message}")
    }
    println("after")
}
