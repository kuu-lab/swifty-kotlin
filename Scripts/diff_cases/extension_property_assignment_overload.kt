var Any.tag: Int
    get() = 100
    set(value) { println("Any $value") }

var String.tag: Int
    get() = 10
    set(value) { println("String $value") }

// Reverse declaration order to ensure selection does not depend on it.
var String.reversedTag: Int
    get() = 20
    set(value) { println("String reversed $value") }

var Any.reversedTag: Int
    get() = 200
    set(value) { println("Any reversed $value") }

fun main() {
    "x".tag = 1
    "x".tag += 2
    "x".tag++
    "x".reversedTag = 3
    "x".reversedTag += 4
    "x".reversedTag++
}
