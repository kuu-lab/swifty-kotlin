fun printErased(value: Any?) {
    println(value)
    println(value.toString())
    println("$value")
}

fun printProgression(value: CharProgression) {
    println(value)
    println(value.toString())
    println("$value")
    printErased(value)
}

fun main() {
    val range = 'a'..'z'
    println(range)
    println(range.toString())
    println("$range")
    println(range.first)
    println("${range.first}..${range.last}")
    printProgression(range)

    val ascending = 'a'..'z' step 2
    println(ascending)
    println(ascending.toString())
    printProgression(ascending)

    val descending = 'z' downTo 'a' step 3
    println(descending)
    println(descending.toString())
    printProgression(descending)

    printProgression('a'..'z' step 1)
    printProgression(CharProgression.fromClosedRange('z', 'a', -1))
    printProgression('z'..'a')
    printProgression('a'..'a')
    printProgression('z'..'a' step 2)
    printProgression('a' downTo 'z' step 3)
    printProgression('\u03B1'..'\u03B6' step 2)
    printProgression('\u03B6' downTo '\u03B1' step 2)
    printProgression('\u3042'..'\u3046')
    printProgression(CharProgression.fromClosedRange('\uFFFD', Char.MAX_VALUE, 2))
    printErased(null)

    printErased(97..122)
    printErased(97..122 step 2)
    printErased(122 downTo 97 step 3)
    printErased(97L..122L step 2)
    printErased(97u..122u step 2)
    printErased(97uL..122uL step 2)
}
