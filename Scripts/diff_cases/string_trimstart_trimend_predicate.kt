fun main() {
    println("[" + "xxhelloxy".trim { it == 'x' || it == 'y' } + "]")
    println("[" + "xxhelloxy".trimStart { it == 'x' || it == 'y' } + "]")
    println("[" + "xxhelloxy".trimEnd { it == 'x' || it == 'y' } + "]")
    println("[" + "".trim { it == 'x' } + "]")
    println("[" + "aba".trim { it == 'a' } + "]")
}
