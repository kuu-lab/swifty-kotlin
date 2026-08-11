fun main() {
    println('a'.uppercaseChar())
    println('A'.lowercaseChar())
    println('z'.uppercaseChar())
    println('1'.uppercaseChar())
    println('ß'.uppercaseChar())
    println('\u01C6'.titlecaseChar())
    println('a'.titlecaseChar())

    println('a'.uppercase())
    println('A'.lowercase())
    println('ß'.uppercase())
    println('\u01C6'.titlecase())
    println('a'.titlecase())

    println('7'.digitToInt())
    println('0'.digitToInt(10))
    println('f'.digitToInt(16))
    println('F'.digitToInt(16))
    println('z'.digitToInt(36))

    println('z'.digitToIntOrNull())
    println('f'.digitToIntOrNull(16))
    println('g'.digitToIntOrNull(16))
    println('-'.digitToIntOrNull(10))

    println(7.digitToChar())
    println(10.digitToChar(16))
    println(35.digitToChar(36))

    try {
        'x'.digitToInt()
    } catch (e: IllegalArgumentException) {
        println("digitToInt-invalid-char")
    }
    try {
        '1'.digitToInt(1)
    } catch (e: IllegalArgumentException) {
        println("digitToInt-invalid-radix")
    }
    try {
        '1'.digitToIntOrNull(37)
    } catch (e: IllegalArgumentException) {
        println("digitToIntOrNull-invalid-radix")
    }
    try {
        16.digitToChar(10)
    } catch (e: IllegalArgumentException) {
        println("digitToChar-invalid-digit")
    }
    try {
        1.digitToChar(40)
    } catch (e: IllegalArgumentException) {
        println("digitToChar-invalid-radix")
    }
}
