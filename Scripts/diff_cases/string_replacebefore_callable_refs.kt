// DIFF_JVM
// DIFF_SKIP_NATIVE: JVM text-operation callable-reference regression
fun main() {
    val before: (String, String, String, String) -> String = String::replaceBefore
    val after: (String, String, String, String) -> String = String::replaceAfter
    val beforeLast: (String, String, String, String) -> String = String::replaceBeforeLast
    val afterLast: (String, String, String, String) -> String = String::replaceAfterLast
    println(before("a:b:c", ":", "X", "MISS"))
    println(after("a:b:c", ":", "X", "MISS"))
    println(beforeLast("a:b:c", ":", "X", "MISS"))
    println(afterLast("a:b:c", ":", "X", "MISS"))
    val beforeChar: (String, Char, String, String) -> String = String::replaceBefore
    val afterChar: (String, Char, String, String) -> String = String::replaceAfter
    println(beforeChar("a:b:c", ':', "Y", "MISS"))
    println(afterChar("a:b:c", ':', "Y", "MISS"))
    val boundBefore: (String, String, String) -> String = "a:b:c"::replaceBefore
    val boundAfterLast: (String, String, String) -> String = "a:b:c"::replaceAfterLast
    println(boundBefore(":", "Z", "MISS"))
    println(boundAfterLast(":", "Z", "MISS"))
}
