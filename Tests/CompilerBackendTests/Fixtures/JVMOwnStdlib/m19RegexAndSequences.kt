fun main() {
    val r = Regex("(?<word>[a-z]+)([0-9]+)?", RegexOption.IGNORE_CASE)
    println(r.pattern); println(r.matches("ABC12")); println(r.containsMatchIn("!ab!"))
    val m = r.find("!Ab12!")!!; println(m.value); println(m.range.first); println(m.range.last)
    println(m.groups["word"]!!.value); println(m.groupValues); println(m.groups[2]!!.value)
    println(r.findAll("a1 b2").map { it.value }.toList())
    println(Regex("[0-9]+").replace("a12b3") { "[${it.value}]" })
    println("a12b3".replace(Regex("[0-9]+"), "!"))
    println(",a,,".split(",".toRegex())); println(Regex.escape("a.b"))
    println(Regex("a").matchAt("ba", 0)); println(Regex("a").matchAt("ba", 1)!!.value)
    for (m in Regex("").findAll("aa")) println(m.range.first)
    println(Regex("a").find("bb")); println("ABC".matches(Regex("abc", RegexOption.IGNORE_CASE)))
}
