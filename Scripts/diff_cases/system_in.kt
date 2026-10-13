// KUU-2017: the exact property-only reproducer must not consume standard input.
// DIFF_STDIN_EOF
fun main() { val input = System.`in`; println(input != null) }
