fun effect() { println("effect") }
fun input(n: Int): Int { println("arg$n"); return n }
fun main() {
    val special = StringBuilder("abc")
    println(special.get(index = 0)); special.set(index = 0, value = 'A')
    println(special.subSequence(startIndex = 0, endIndex = 2)); println(special.substring(startIndex = 1))
    println(special.indexOf(string = "B", startIndex = 0, ignoreCase = true)); println(special.lastIndexOf('c'))
    println(special.isNotEmpty()); println(special.last()); println(special.lastIndex)
    val chars = charArrayOf('A', 'B', 'C', 'D'); val nullable: CharArray? = chars
    val b = StringBuilder(2); b.append(nullable); println(b)
    val any: Any? = chars; b.clear().append(any); println(b.toString().startsWith("[C@"))
    b.clear().appendRange(chars, 1, 3).appendRange("wxyz", 1, 3); println(b)
    b.insertRange(1, chars, 1, 3).insertRange(0, "wxyz", 2, 4); println(b)
    b.setRange(0, 2, "!"); println(b.substring(0, 3)); println(b.indexOf("C")); println(b.lastIndexOf("y"))
    b.clear().append(effect()); println(b)
    b.clear().appendLine('A').appendLine(42).appendLine(); println(b.toString().replace("\n", "/"))
    b.clear().appendCodePoint(0x1f600); println(b); println(b.length)
    b.clear().append("x"); b.setLength(3); println(b[1].code); b.setLength(1); println(b)
    try { val a: CharArray? = null; b.append(a) } catch (e: NullPointerException) { println("nullarray") }
    try { b[9] = 'a' } catch (e: IndexOutOfBoundsException) { println("set") }
    try { b.deleteAt(9) } catch (e: IndexOutOfBoundsException) { println("delete") }
    try { b.appendRange(chars, 3, 2) } catch (e: IndexOutOfBoundsException) { println("range") }
    println(buildString(capacity = input(1), builderAction = { append('a'); append(length) }))
    try { buildString(-1) { append('x') } } catch (e: NegativeArraySizeException) { println("capacity") }
}
