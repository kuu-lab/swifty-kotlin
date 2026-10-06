operator fun Char.times(other: Int): Int = code * other
operator fun Char.plus(other: Char): Char = (code + other.code).toChar()

fun Char.implicitCode(): Int = code
fun Char.explicitCode(): Int = this.code
val Char.codeProperty: Int get() = code
fun Char.capturedCode(): Int {
    val read = { code }
    return read()
}
fun Char.parameterCode(code: Int): Int = code
fun Char.localCode(): Int {
    val code = 7
    return code
}

class CodeOwner(val code: Int) {
    fun memberCode(): Int = code
    fun Char.extensionCode(): Int = code
    fun readExtension(): Int = 'a'.extensionCode()
}

fun main() {
    println('a' * 2)
    println(('a' + 'b').code)
    for (char in charArrayOf('\u0000', 'a', '\u03A9', '\uD800', '\uFFFF')) {
        println(char.implicitCode())
        println(char.explicitCode())
        println(char.codeProperty)
        println(char.capturedCode())
        println(char * 2)
    }
    println('a'.parameterCode(42))
    println('a'.localCode())
    val owner = CodeOwner(1234)
    println(owner.memberCode())
    println(owner.readExtension())
    val boxed: Any = 'z'
    println((boxed as Char).implicitCode())
    println('b'.run { code })
    println(with('c') { code })
}
