import kotlinx.io.files.SystemPathSeparator

fun systemPathSeparatorBinding() {
    val first: Char = SystemPathSeparator
    val second: Char = SystemPathSeparator

    check(first == second) { "SystemPathSeparator reads must have the same Char value" }

    println("SystemPathSeparator:type=Char")
    println("SystemPathSeparator:value=$first")
    println("SystemPathSeparator:repeated-read=stable")
}

fun main() = systemPathSeparatorBinding()
