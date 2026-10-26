fun concatAny(x: Any) = "$x!!"
fun <T : String> concat1(x: T) = "[[$x]]"
fun <T : String?> concat2(x: T) = "[[$x]]"
fun <T : String> concat3(x: T?) = "[[$x]]"

fun <T : String> concat4(x: T) = x + "!!"
fun <T : String?> concat5(x: T) = x + "!!"
fun <T : String> concat6(x: T?) = x + "!!"
fun <T : String?> concatNamed(value: T): String = value.plus("!!")

fun box(): String {
    if (concat1("1") != "[[1]]") throw IllegalStateException("concat1")
    if (concat2("2") != "[[2]]") throw IllegalStateException("concat2")
    if (concat2(null) != "[[null]]") throw IllegalStateException("concat2 null")
    if (concat3("3") != "[[3]]") throw IllegalStateException("concat3")
    if (concat3(null) != "[[null]]") throw IllegalStateException("concat3 null")
    if (concat4("4") != "4!!") throw IllegalStateException("concat4")
    if (concat5("5") != "5!!") throw IllegalStateException("concat5")
    if (concat5("null") != "null!!") throw IllegalStateException("concat5 null text")
    if (concat5("6") != "6!!") throw IllegalStateException("concat5 again")
    if (concat6<String>(null) != "null!!") throw IllegalStateException("concat6")
    return "OK"
}

fun main() {
    println(box())
    println(concat5<String?>(null))
    println(concat5<String?>("K"))
    println(concatNamed<String?>(null))
}
