class Box {
    var text = "A"
        get() { println("get"); return field }
        set(value) { println("set:$value"); field = value }
    fun fieldAdd(value: Any?) { fieldText += value }
    var fieldText = "F"
}
fun box(value: Box): Box { println("receiver"); return value }
fun rhs(value: Box): Int { println("rhs"); value.text = "changed"; return 2 }
fun effect() { println("unit") }
fun index(n: Int): Int { println("index$n"); return n }
fun mutate(array: Array<String>): Boolean { array[0] = ";"; return false }
fun mutateChar(array: CharArray): Char { array[0] = 'y'; return 'z' }
fun mutateString(array: Array<String>): String { array[0] = ";"; return "|" }
class Bad { override fun toString(): String { throw IllegalStateException("render") } }
class Custom { operator fun plus(n: Int): String = "custom:$n" }
fun early(): String { return "before${return "early"}after" }
fun short(flag: Boolean): String { return "${flag && (return "early")}" }
fun shortOr(flag: Boolean): String { return "${flag || (return "early")}" }
fun loop(flag: Boolean): String {
    do { if (flag) break } while ("${return "early"}" == "x")
    return "done"
}
fun fromBody(): String { do { return "body" } while ("${throw IllegalStateException("bad")}" == "x") }
fun choose(flag: Boolean): String {
    val value = when { flag -> "chosen"; ("${return "early"}" == "x") -> "bad"; else -> "bad" }
    return "when:$value"
}
fun chooseMulti(value: String): String {
    val result = when (value) { "a", "${return "early"}" -> "chosen"; else -> "bad" }
    return "multi:$result"
}
fun main() {
    var text = "x"; text += 1; text += null; text += effect(); println(text)
    val box = Box(); box(box).text += rhs(box); println(box.text)
    box.fieldAdd(3); println(box.fieldText)
    val array = arrayOf("a"); array[0] += 2; println(array[0])
    val list = mutableListOf("l"); list[0] += true; println(list[0])
    val map = mutableMapOf(1 to "m"); map[1] += 3; map[2] += "x"; println(map[1]); println(map[2])
    var captured = "C"; val read = { captured += "!"; "$captured" }; println(read()); println(read())
    val obj = object { fun show(): String = "object:$captured" }; println(obj.show())
    try { println("${Bad()}${effect()}") } catch (e: IllegalStateException) { println(e.message) }
    try { println("${throw IllegalStateException("throw")}bad") } catch (e: IllegalStateException) { println(e.message) }
    println(early()); println(short(false)); println(short(true)); println(shortOr(true)); println(shortOr(false)); println(loop(true)); println(loop(false)); println(fromBody()); println(choose(true)); println(choose(false)); println(chooseMulti("a")); println(chooseMulti("b")); println(Custom() + 2)
    val any: Any? = "x"; println("x".equals(any)); println("x".equals(null)); println("x".equals("x"))
    println("hello".substring(endIndex = index(4), startIndex = index(1)))
    val delimiters = arrayOf(",")
    println("a,b;c".split(*delimiters, ignoreCase = mutate(delimiters)))
    println("a,b;c".split(delimiters = arrayOf(";"), limit = 2))
    val named = arrayOf(",")
    println("a,b;c".split(delimiters = named, ignoreCase = mutate(named)))
    val chars = charArrayOf('x'); println("xyz".trim(*chars, mutateChar(chars)))
    val strings = arrayOf(","); println("a,b;c|d".split(*strings, mutateString(strings)))
}
