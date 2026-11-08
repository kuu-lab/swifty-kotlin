fun Char.code(): Int = this.code + 10
fun Char.category(): Int = 20
fun Char.directionality(): Int = 30

fun main() {
    val value: Char? = 'a'
    println('a'.code())
    println(value?.code())
    println('a'.category())
    println('a'.directionality())
    println('a'.code)
    println(value?.code)
    println('a'.category)
    println(value?.directionality)
}
