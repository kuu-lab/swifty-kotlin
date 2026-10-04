fun main() {
    val repeatedIndent = "\n\n  a\n  b\n\n"
    println("trimIndent=" + repeatedIndent.trimIndent().replace("\n", "/"))
    println("replaceIndent=" + repeatedIndent.replaceIndent(">>").replace("\n", "/"))

    val repeatedMargin = "\n\n  |a\n  |b\n\n"
    println("trimMargin=" + repeatedMargin.trimMargin().replace("\n", "/"))
    println("replaceIndentByMargin=" + repeatedMargin.replaceIndentByMargin(">>").replace("\n", "/"))

    val unicodeBlankEdges = "\u00A0\n\u00A0\n  a\n  b\n\u00A0\n\u00A0"
    println("unicodeBlankEdges=" + unicodeBlankEdges.trimIndent().replace("\n", "/"))

    val unicodeIndent = "\n\u00A0\u00A0a\n\u00A0\u00A0b\n"
    println("unicodeTrimIndent=" + unicodeIndent.trimIndent().replace("\n", "/"))

    val unicodeMargin = "\n\u00A0\u00A0|a\n\u00A0\u00A0|b\n"
    println("unicodeTrimMargin=" + unicodeMargin.trimMargin().replace("\n", "/"))
}
