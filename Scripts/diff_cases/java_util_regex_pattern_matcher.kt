import java.util.regex.Pattern
import java.util.regex.Matcher

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

    val caseInsensitive = Pattern.compile("a+", Pattern.CASE_INSENSITIVE)
    println(caseInsensitive.pattern())
    println(caseInsensitive.flags())
    println(caseInsensitive.matcher("AAA").matches())
    println(Pattern.matches("a+", "aaa"))
    println(Pattern.matches("a+", "baaa"))

    val comma = Pattern.compile(",")
    println(comma.split("a,b,,").joinToString("|"))
    println(comma.split("a,b,,", -1).joinToString("|"))
    println(comma.split("a,b,c", 2).joinToString("|"))
    println(Pattern.compile("^").split("abc").joinToString("|"))
    println(Pattern.compile("").split("abc").joinToString("|"))

    val quotedPattern = Pattern.quote("a.E\\E")
    println(Pattern.compile(quotedPattern).matcher("a.E\\E").matches())
    println(Pattern.compile("[a-z]+").matcher("word42").lookingAt())

    val findAt = Pattern.compile("[a-z]+").matcher("12word34")
    println(findAt.find(2))
    println(findAt.group())
    println(findAt.start())

    println(Pattern.compile("\\d+").matcher("a12b34").replaceAll("x"))
    println(Pattern.compile("\\d+").matcher("a12b34").replaceFirst("x"))
    println(Pattern.compile("x").matcher("x").replaceAll(Matcher.quoteReplacement("$" + "1")))

    val appendMatcher = Pattern.compile("(?<digits>\\d+)").matcher("a12b34")
    val appendBuffer = StringBuilder()
    val namedReplacement = "<" + '$' + "{digits}>"
    while (appendMatcher.find()) appendMatcher.appendReplacement(appendBuffer, namedReplacement)
    appendMatcher.appendTail(appendBuffer)
    println(appendBuffer.toString())
}
