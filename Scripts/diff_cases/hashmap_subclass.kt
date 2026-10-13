class MyStrMap : HashMap<String, Int>()

fun main() {
    val mm = MyStrMap()
    mm["k"] = 5
    println(mm["k"])
}
