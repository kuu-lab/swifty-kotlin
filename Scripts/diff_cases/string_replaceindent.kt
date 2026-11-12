// DIFF_JVM
fun main() {
    println("a\n b".replaceIndent("&gt;"))
    println("---")
    println("\n    alpha\n      beta\n   gamma\n".replaceIndent(">>"))
    println("  alpha\n\n    beta\n".replaceIndent("x"))
    println("  first\n    \n  last".replaceIndent("|").replace(" ", "_"))
    println(" \n   \n".replaceIndent("!").replace(" ", "_"))
    println("<" + "".replaceIndent(">") + ">")
    println("  default\n  value".replaceIndent())
    println("plain\n  indented\n".replaceIndent(">"))
    println("  first\r\n    second\r third\n".replaceIndent("|").replace("\n", "/"))
}
