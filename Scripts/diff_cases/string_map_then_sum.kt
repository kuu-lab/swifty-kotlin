// KUU-2331: String.map returns a numeric List that can be summed.
fun main() {
    println("1234".map { it - '0' }.sum())
}
