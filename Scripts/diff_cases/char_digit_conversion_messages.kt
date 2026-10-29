// digitToInt/digitToChar exception messages must match the JVM stdlib:
// the radix-10 overloads say "decimal digit", the explicit-radix ones say
// "Char X is not a digit in the given radix=N" / "Digit N does not represent
// a valid digit in radix R", and digitToChar's own radix check uses
// "Invalid radix: R. ..." while checkRadix uses "radix R was not in valid
// range 2..36".
fun tryEach(f: () -> Unit) {
    try {
        f()
        println("ok")
    } catch (e: Exception) {
        println(e.message)
    }
}

fun main() {
    tryEach { '9'.digitToInt(2) }
    tryEach { 'a'.digitToInt(10) }
    tryEach { Char.MIN_VALUE.digitToInt() }
    tryEach { 'G'.digitToInt(16) }
    tryEach { ' '.digitToInt() }
    tryEach { 'ß'.digitToInt(36) }
    tryEach { '⑦'.digitToInt() }
    tryEach { '⑤'.digitToInt(8) }
    tryEach { 10.digitToChar(10) }
    tryEach { 36.digitToChar(36) }
    tryEach { (-1).digitToChar() }
    tryEach { 10.digitToChar() }
    tryEach { 5.digitToChar(1) }
    tryEach { 5.digitToChar(37) }
    tryEach { '5'.digitToInt(1) }
    tryEach { '5'.digitToInt(37) }
    tryEach { '5'.digitToIntOrNull(37) }
    tryEach { '5'.digitToIntOrNull(0) }
    tryEach { println(35.digitToChar(36)) }
    tryEach { println('ｆ'.digitToInt(16)) }
    tryEach { println('z'.digitToInt(36)) }
    tryEach { println(9.digitToChar()) }
    tryEach { println('5'.digitToInt()) }
    tryEach { println('٣'.digitToInt()) }
}
