// KUU-4448: every constructor form declared by the bundled collection
// classes must keep compiling — the Sema viability probe added for the
// arity fix must not reject valid calls.
fun main() {
    println(ArrayList<Int>().size)
    println(ArrayList<Int>(10).size)
    println(ArrayList(listOf(1, 2, 3)).size)
    println(ArrayList<String>(listOf("a")).size)
    println(HashSet<Int>().size)
    println(HashSet<Int>(16).size)
    println(HashSet<Int>(16, 0.5f).size)
    println(HashSet(listOf("a", "b")).size)
    println(LinkedHashSet<Int>().size)
    println(LinkedHashSet<Int>(4).size)
    println(LinkedHashSet(listOf(7, 8)).size)
    println(HashMap<String, Int>().size)
    println(HashMap<String, Int>(8).size)
    println(HashMap<String, Int>(8, 0.5f).size)
    println(HashMap(mapOf("a" to 1, "b" to 2)).size)
    println(LinkedHashMap<String, Int>().size)
    println(LinkedHashMap<String, Int>(8).size)
    println(LinkedHashMap<String, Int>(8, 0.5f).size)
    println(LinkedHashMap(mapOf("b" to 2)).size)
    val a: ArrayList<String> = ArrayList()
    val h: HashMap<Int, String> = HashMap()
    println(a.size + h.size)
}
