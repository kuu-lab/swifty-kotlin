fun main() {
    var calls = 0
    val failure = runCatching { "abacad".single { calls++; it == 'a' } }.exceptionOrNull()
    println("${failure?.javaClass?.simpleName} ${failure?.message} $calls")

    calls = 0
    println("${"abacad".singleOrNull { calls++; it == 'a' }} $calls")

    calls = 0
    println("${"xyz".single { calls++; it == 'y' }} $calls")

    calls = 0
    println("${"xyz".singleOrNull { calls++; it == 'q' }} $calls")

    val missing = runCatching { "xyz".single { it == 'q' } }.exceptionOrNull()
    println("${missing?.javaClass?.simpleName} ${missing?.message}")

    calls = 0
    val cs: CharSequence = StringBuilder("abacad")
    println("${cs.singleOrNull { calls++; it == 'a' }} $calls")
}
