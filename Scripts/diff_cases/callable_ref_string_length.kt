fun lengthFunction(): (String) -> Int = String::length
fun bracket(value: String): String = "[$value]"

fun main() {
    println(listOf("a", "bb").map(String::length))
    val length: (String) -> Int = String::length
    println(length("abc"))
    println(listOf("", "kotlin").map(length))
    val property = String::length
    println(property.get("abcd"))
    println(property("abcde"))
    println(listOf("", "🙂", "e\u0301").map(String::length))
    val bound = "kotlin"::length
    println(bound.get())
    println(bound())
    println("direct".length)
    println(lengthFunction()("return"))
    println(listOf("x", "yy").map(::bracket))
    println(bracket("z"))
}
