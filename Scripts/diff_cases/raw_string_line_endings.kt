fun codes(s: String) = s.map { it.code }.joinToString(",")

fun main() {
    val lf = """a
b"""
    val crlf = """a
b"""
    val cr = """ab"""
    val mixed = """x
y
zw"""
    val blankEdges = """
first

last
"""
    val name = "K"
    val tpl = """a
$name
b"""
    val escaped = "\r\n"
    println("lf=" + codes(lf))
    println("crlf=" + codes(crlf))
    println("cr=" + codes(cr))
    println("mixed=" + codes(mixed))
    println("blankEdges=" + codes(blankEdges))
    println("tpl=" + codes(tpl))
    println("escaped=" + codes(escaped))
    println("trimIndent=" + blankEdges.trimIndent().length)
}
