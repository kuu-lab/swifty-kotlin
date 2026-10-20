fun limit(): Int { println("limit"); return 2 }
fun input(): String { println("input"); return "a,b,c" }
fun main() {
    val empty = Regex(""); println(empty.findAll("😀").map { it.range.first }.toList())
    val m = Regex(".").find("😀")!!; println(m.range.first); println(m.range.last); println(m.range.start); println(m.range.endInclusive)
    println(empty.split("aa")); println(empty.replace("aa", "-"))
    println(Regex("a*").findAll("aa").map { "${it.value}:${it.range.first}:${it.range.last}" }.toList())
    val r = Regex("(?<letter>[a-z])([0-9])?"); val match = r.find("a")!!
    println(match.groups.size); println(match.groups[2]); println(match.groupValues[2]); println(match.groups["letter"]!!.value)
    val (letter, number) = match.destructured; println("$letter/$number"); println(match.destructured.toList())
    println(Regex("([a-z])").replace("ab", "$1$1"))
    println(Regex("([a-z])").replace("ab") { "$1" })
    var n = 0; val seq = Regex("[a-z]").findAll("a b c").filter { n++; it.value != "b" }.map { it.value.uppercase() }
    println(n); println(seq.toList()); println(n); println(seq.first()); println(n)
    println(Regex(",").split(limit = limit(), input = input()))
    println("a,b,c".split(regex = Regex(","), limit = 2)); println("a,b,".splitToSequence(Regex(",")).toList())
    println("ABC" matches Regex("abc", setOf(RegexOption.IGNORE_CASE)))
    println(Regex.fromLiteral("a.b").matches("a.b")); println(Regex.escapeReplacement("$1"))
    println(Regex("a").find("aa")!!.next()!!.value); println(Regex("a").findAll("bbb").firstOrNull())
    try { Regex("[") } catch (e: IllegalArgumentException) { println("pattern") }
    try { Regex("a").find("a", -1) } catch (e: IndexOutOfBoundsException) { println("index") }
    try { Regex(",").split("a", -1) } catch (e: IllegalArgumentException) { println("split") }
    try { "abc".windowed(0) } catch (e: IllegalArgumentException) { println("window") }
    try { "abc".windowed(1, step = 0) } catch (e: IllegalArgumentException) { println("step") }
}
