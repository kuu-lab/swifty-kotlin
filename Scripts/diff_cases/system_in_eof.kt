// KUU-2017: standard input is a stable InputStream object and reports EOF.
// DIFF_STDIN_EOF
fun main() {
    val input: java.io.InputStream = java.lang.System.`in`
    println(input === System.`in`)
    println(input.read())
    println(input.read())
    println(readLine())
    java.lang.System.gc()
}
