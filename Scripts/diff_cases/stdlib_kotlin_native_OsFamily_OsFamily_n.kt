// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are unavailable in the JVM kotlinc reference environment.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.OsFamily

fun main() {
    println(OsFamily.entries.size)
    println(OsFamily.values().size)
    println(OsFamily.valueOf("TVOS"))
}
