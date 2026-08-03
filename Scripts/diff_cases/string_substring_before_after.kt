fun main() {
    println("hello.world.kt".substringBefore("."))
    println("hello.world.kt".substringAfter("."))
    println("hello.world.kt".substringBeforeLast("."))
    println("hello.world.kt".substringAfterLast("."))

    // String delimiter, not found: default missingDelimiterValue = this.
    println("nodelimiter".substringBefore("."))
    println("nodelimiter".substringAfter("."))
    println("nodelimiter".substringBeforeLast("."))
    println("nodelimiter".substringAfterLast("."))

    // String delimiter, not found: explicit missingDelimiterValue.
    println("nodelimiter".substringBefore(".", "MISS"))
    println("nodelimiter".substringAfter(".", "MISS"))
    println("nodelimiter".substringBeforeLast(".", "MISS"))
    println("nodelimiter".substringAfterLast(".", "MISS"))

    // Char delimiter, found and not found.
    println("hello.world.kt".substringBefore('.'))
    println("hello.world.kt".substringAfter('.'))
    println("hello.world.kt".substringBeforeLast('.'))
    println("hello.world.kt".substringAfterLast('.'))
    println("nodelimiter".substringBefore('.', "MISS"))
    println("nodelimiter".substringAfter('.', "MISS"))
    println("nodelimiter".substringBeforeLast('.', "MISS"))
    println("nodelimiter".substringAfterLast('.', "MISS"))

    // Multiple occurrences: before/after pick the first, beforeLast/afterLast the last.
    println("a.b.c.d".substringBefore("."))
    println("a.b.c.d".substringAfter("."))
    println("a.b.c.d".substringBeforeLast("."))
    println("a.b.c.d".substringAfterLast("."))

    // Multi-character String delimiter.
    println("key::value::extra".substringBefore("::"))
    println("key::value::extra".substringAfter("::"))
    println("key::value::extra".substringBeforeLast("::"))
    println("key::value::extra".substringAfterLast("::"))

    // Empty String delimiter.
    println("abc".substringBefore(""))
    println("abc".substringAfter(""))
    println("abc".substringBeforeLast(""))
    println("abc".substringAfterLast(""))
    println("".substringBefore(""))
    println("".substringAfter(""))
    println("".substringBeforeLast(""))
    println("".substringAfterLast(""))
}
