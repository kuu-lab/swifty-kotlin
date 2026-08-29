// SKIP-DIFF (DEBT-DIFF-001): Kotlin 2.3.10 keeps HexFormat.Builder's no-arg
// constructor @PublishedApi internal, so an external JVM kotlinc module
// rejects this direct constructor call. The focused Sema Golden and direct
// kswiftc execution cover the candidate path instead.

import kotlin.text.HexFormat

fun main() {
    println(HexFormat.Builder())
}
