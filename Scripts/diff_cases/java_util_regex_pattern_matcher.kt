import java.util.regex.Pattern

fun main() {
    val matcher = Pattern.compile("[a-z]+").matcher("12word34")
    matcher.region(2, 6)
    println(matcher.find())
    println(matcher.end())
    println(matcher.group())
    println(matcher.start())
    println(matcher.find())

    matcher.reset("a42b")
    println(matcher.find())
    println(matcher.group())
    println(matcher.start())
    println(matcher.end())

    val outOfRegion = Pattern.compile("word").matcher("12word34").region(0, 4)
    println(outOfRegion.find())
    try {
        outOfRegion.end()
        println("missing-match-end")
    } catch (exception: IllegalStateException) {
        println("illegal-state")
    }

    val anchored = Pattern.compile("^word$").matcher("12word34").region(2, 6)
    println(anchored.find())
    println(anchored.group())

    val adapted = Regex("word", RegexOption.IGNORE_CASE).toPattern().matcher("WORD")
    println(adapted.find())
    println(adapted.group())
}
