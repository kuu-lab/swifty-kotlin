fun main() {
    println('é'.code)
    println('あ'.code)
    println('\uD7FF'.code)
    println('\uE000'.code)
    println('\uFFFF'.code)
    println('\uD800'.code)
    println('\uDBFF'.code)
    println('\uDC00'.code)
    println('\uDFFF'.code)
    println('\uD800'.isHighSurrogate())
    println('\uDC00'.isLowSurrogate())
    println("😀𝒜")
}
