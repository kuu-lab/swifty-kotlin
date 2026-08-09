class Tag(val label: String)

fun applyInt(block: context(Int) () -> String): String = "applyInt"

fun applyTag(prefix: String, block: context(Tag) () -> Int): String = prefix + "/applyTag"

fun main() {
    println(applyInt { "unused" })
    println(applyTag("p") { 0 })
}
