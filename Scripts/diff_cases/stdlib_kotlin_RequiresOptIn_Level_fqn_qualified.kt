package diff

fun levelEntries(): kotlin.enums.EnumEntries<kotlin.RequiresOptIn.Level> =
    kotlin.RequiresOptIn.Level.entries

fun levelValueOf(): kotlin.RequiresOptIn.Level =
    kotlin.RequiresOptIn.Level.valueOf("WARNING")

fun levelValues(): Array<kotlin.RequiresOptIn.Level> =
    kotlin.RequiresOptIn.Level.values()

fun main() {
    println(levelEntries())
    println(levelValueOf())
    println(levelValues().toList())
}
