package golden.sema

fun topLevelRun(): Int = run { 41 }

fun receiverRun(): Int = "hello".run { length }

fun receiverRunCatching(): Result<Int> = "hello".runCatching { length }

fun main() {
    println(topLevelRun())
    println(receiverRun())
    println(receiverRunCatching().getOrThrow())
}
