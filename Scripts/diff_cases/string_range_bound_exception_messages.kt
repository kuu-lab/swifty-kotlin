fun main() {
    val s = "abcdef"
    val sb = StringBuilder("abcdef")
    val cs: CharSequence = s
    val api = listOf<Pair<String, () -> String>>(
        "s.substring(-3)" to { s.substring(-3) },
        "s.substring(7)" to { s.substring(7) },
        "s.substring(0,-1)" to { s.substring(0, -1) },
        "s.substring(4,2)" to { s.substring(4, 2) },
        "s.substring(0,7)" to { s.substring(0, 7) },
        "s.substring(6)" to { s.substring(6) },
        "s.substring(1,4)" to { s.substring(1, 4) },
        "s.subSequence(-1,2)" to { s.subSequence(-1, 2).toString() },
        "s.subSequence(0,7)" to { s.subSequence(0, 7).toString() },
        "cs.subSequence(0,7)" to { cs.subSequence(0, 7).toString() },
        "sb.subSequence(0,7)" to { sb.subSequence(0, 7).toString() },
        "sb.subSequence(4,2)" to { sb.subSequence(4, 2).toString() },
        "s[6]" to { s[6].toString() },
        "s[-1]" to { s[-1].toString() },
        "cs[6]" to { cs[6].toString() },
        "s.slice(listOf(6))" to { s.slice(listOf(6)) },
        "s.slice(listOf(-1))" to { s.slice(listOf(-1)) },
        "s.slice(4..9)" to { s.slice(4..9) },
        "s.slice(1..3)" to { s.slice(1..3) },
        "s.removeRange(-1,2)" to { s.removeRange(-1, 2) },
        "s.removeRange(4,7)" to { s.removeRange(4, 7) },
        "s.removeRange(0,7)" to { s.removeRange(0, 7) },
        "s.removeRange(0,10)" to { s.removeRange(0, 10) },
        "s.removeRange(7,7)" to { s.removeRange(7, 7) },
        "s.removeRange(-1,100)" to { s.removeRange(-1, 100) },
        "s.removeRange(7,8)" to { s.removeRange(7, 8) },
        "s.removeRange(2,1)" to { s.removeRange(2, 1) },
        "s.removeRange(1,4)" to { s.removeRange(1, 4) },
        "cs.removeRange(0,7)" to { cs.removeRange(0, 7).toString() },
        "cs.removeRange(7,7)" to { cs.removeRange(7, 7).toString() },
        "s.replaceRange(-1,2,x)" to { s.replaceRange(-1, 2, "x") },
        "s.replaceRange(4,7,x)" to { s.replaceRange(4, 7, "x") },
        "s.replaceRange(7,7,x)" to { s.replaceRange(7, 7, "x") },
        "s.replaceRange(0,-1,x)" to { s.replaceRange(0, -1, "x") },
        "s.replaceRange(-1,100,x)" to { s.replaceRange(-1, 100, "x") },
        "s.replaceRange(1,4,XY)" to { s.replaceRange(1, 4, "XY") },
        "cs.replaceRange(0,7,x)" to { cs.replaceRange(0, 7, "x").toString() },
        "cs.replaceRange(2,1,x)" to { cs.replaceRange(2, 1, "x").toString() }
    )
    for ((name, f) in api) {
        try { println(name + " -> [" + f() + "]") }
        catch (e: Exception) { println(name + " -> " + e::class.simpleName + ": " + e.message) }
    }
}
