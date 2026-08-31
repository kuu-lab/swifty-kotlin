package diff

fun levelValues(): Array<kotlin.RequiresOptIn.Level> =
    kotlin.RequiresOptIn.Level.values()

fun main() {
    println(levelValues().toList())
}
