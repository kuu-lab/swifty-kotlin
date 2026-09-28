fun main() {
    val empty: ArrayList<String?> = arrayListOf()
    empty.add(null)
    empty.add("ready")
    println(empty)
    val values: ArrayList<Int> = arrayListOf(3, 1, 3)
    values.add(4)
    println(values)
    println(arrayListOf<Int>().size)
}
