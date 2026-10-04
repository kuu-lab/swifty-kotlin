@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.OsFamily

fun main() {
    println(OsFamily.entries.size)
    println(OsFamily.values().size)
    println(OsFamily.valueOf("TVOS"))
}
