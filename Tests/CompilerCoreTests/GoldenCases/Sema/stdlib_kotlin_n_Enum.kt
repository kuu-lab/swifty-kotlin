package golden.sema

fun <T : Enum<T>> identity(value: T): T = value

fun main() {
    println("ok")
}
