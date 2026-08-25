// SKIP-DIFF (DEBT-DIFF-001): Kotlin 2.3.10 declares HexFormat.Builder's
// constructor @PublishedApi internal, so the external JVM kotlinc reference
// module rejects this direct constructor call. The candidate is checked by
// the focused Sema Golden and direct kswiftc execution instead.

import kotlin.text.HexFormat

fun main() {
    println(HexFormat.Builder())
}
