interface Api<T> { fun number(input: T, suffix: String = "!"): String }
open class IntBase { fun number(input: Int, suffix: String): String = "$input$suffix" }
class IntLeaf: IntBase(), Api<Int>
fun main() {
    val bound: (Int) -> String = IntLeaf()::number
    println(bound(9))
    val unbound: (IntLeaf, Int) -> String = IntLeaf::number
    println(unbound(IntLeaf(), 10))
    val full: (Int, String) -> String = IntBase()::number
    println(full(12, "?"))
}
