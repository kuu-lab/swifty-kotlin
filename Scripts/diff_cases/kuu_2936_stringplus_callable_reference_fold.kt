// KUU-2936: Keep Char rendering when String::plus is adapted to a CharArray fold.
fun box() = charArrayOf('O', 'K').fold("", String::plus)
fun main() { println(box()) }
