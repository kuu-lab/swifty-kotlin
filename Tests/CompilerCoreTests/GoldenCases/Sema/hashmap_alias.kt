fun processMap(map: HashMap<String, Int>) {
    println(map.size)
}

fun createMap(): HashMap<Int, String> {
    return HashMap<Int, String>()
}

class MapHolder {
    val scores: HashMap<String, Int> = HashMap()
    val labels: HashMap<Int, String> = HashMap<Int, String>()
}

fun main() {
    val hm: HashMap<String, Int> = HashMap()
    hm["x"] = 10
    hm["y"] = 20
    val mm: MutableMap<String, Int> = hm
    mm["w"] = 40
    println(mm.size)
    val copy = HashMap(hm)
    println(copy.size)
    println(hm.containsKey("x"))
    println(hm.containsValue(99))
    hm.remove("y")
    println(hm.size)
    println(hm.getOrDefault("missing", -1))
    val empty: HashMap<Int, Int> = HashMap()
    println(empty.isEmpty())

    processMap(hm)

    val created = createMap()
    created[1] = "one"
    println(created.size)

    val holder = MapHolder()
    holder.scores["alice"] = 100
    println(holder.scores.size)
}
