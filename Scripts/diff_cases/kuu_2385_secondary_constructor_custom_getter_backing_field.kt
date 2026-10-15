// KUU-2385: constructor-body writes must update the instance backing field read by a custom getter.
class A {
    val value: String
        get() = field + "K"
    constructor(o: String) {
        value = o
    }
}

class Secondary {
    val value: String get() = field + "K"
    constructor(input: String) { value = input }
}

class Primary(input: String) {
    val value: String = input
        get() = field + "K"
}

class InitBlock(input: String) {
    val value: String get() = field + "K"
    init { value = input }
}

class SecondaryAuto {
    val value: String
    constructor(input: String) { value = input }
}

class SecondarySetter {
    var value: String = "I"
        get() = field + "K"
        set(value) { field = value + "S" }
    constructor(input: String) { value = input }
}

class InitSetter(input: String) {
    var value: String = "I"
        get() = field + "K"
        set(value) { field = value + "S" }
    init { value = input }
}

class DefaultSetter(input: String) {
    var value: String = input
        get() = field + "K"
}

fun box() = A("O").value

fun main() {
    println(box())
    println(listOf(
        Secondary("A").value,
        Secondary("B").value,
        Primary("O").value,
        InitBlock("O").value,
        SecondaryAuto("O").value,
        SecondarySetter("O").value,
        InitSetter("O").value,
        DefaultSetter("O").value
    ).joinToString("|"))
}
