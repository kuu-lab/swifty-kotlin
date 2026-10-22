fun report(block: () -> Any?) { println(block()) }
fun main() { report { println("side") } }
