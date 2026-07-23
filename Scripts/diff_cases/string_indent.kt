fun main() {
    val text = "Hello\nWorld"
    val block = "\n    Hello\n      World\n"
    val margin = "\n    |Hello\n    |World\n"
    println(block.trimIndent())
    println(margin.trimMargin())
    println(margin.trimMargin("|"))
    println(text.prependIndent())
    println(text.prependIndent("  "))
    println(text.prependIndent(">>"))
    // Blank-line semantics (kotlin.stdlib): shorter blank → indent only;
    // blank already >= indent length is preserved unchanged.
    println("a\n\nb".prependIndent("  "))
    println("a\n  \nb".prependIndent(" "))
    println("  Hello\n  World".replaceIndent("    "))
    println("  Hello\n  World".replaceIndent())
    println(margin.replaceIndentByMargin("> ", "|"))
    println(margin.replaceIndentByMargin())
}
