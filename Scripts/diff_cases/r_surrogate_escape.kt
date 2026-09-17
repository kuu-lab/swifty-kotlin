fun main() {
    println("\uD83D".length)
    println("\uD83D".first().code)
    println(("\uD83D" + "\uDE00").length)
    println("x\uD83Dy".length)
    println("\uDC00".length)
    println("\uDC00".first().code)
    println("\uD83D\uDE00".length)
    println("\uD83D\uDE00" == "😀")
    println("\uFFFF".first().code)
    println('\uD83D'.code)
}
