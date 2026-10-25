// DIFF_JVM
// KUU-3413: JVM StringBuilder exposes getChars with source and destination offsets.
fun main() {
    val destination = charArrayOf('_', '_', '_', '_')
    StringBuilder("ab").getChars(0, 2, destination, 1)
    println(destination.concatToString())
}
