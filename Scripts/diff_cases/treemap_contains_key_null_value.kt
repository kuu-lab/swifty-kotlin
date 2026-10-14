import java.util.TreeMap

fun main() {
    val byLength = TreeMap<String, Int?>(Comparator { a, b -> a.length - b.length })
    byLength["a"] = null
    println(byLength.containsKey("b"))
    println(byLength.containsKey("bb"))
    println(byLength["b"])

    val plain = TreeMap<String, Int>()
    plain["x"] = 1
    println(plain.containsKey("x"))
    println(plain.containsKey("y"))
}
