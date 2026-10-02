fun main() {
    val list = mutableListOf(1, 2, 3)
    try {
        for (x in list) {
            if (list.size > 10) break
            list.add(x)
        }
        println("list: not-thrown size=" + list.size)
    } catch (e: ConcurrentModificationException) {
        println("list: caught")
    }

    val map = mutableMapOf(1 to "a", 2 to "b")
    try {
        for ((k, _) in map) {
            if (map.size > 10) break
            map[k + 10] = "z"
        }
        println("map: not-thrown size=" + map.size)
    } catch (e: ConcurrentModificationException) {
        println("map: caught")
    }

    val set = mutableSetOf(1, 2, 3)
    try {
        for (x in set) {
            if (set.size > 10) break
            set.add(x + 10)
        }
        println("set: not-thrown size=" + set.size)
    } catch (e: ConcurrentModificationException) {
        println("set: caught")
    }

    val listRemoval = mutableListOf(1, 2, 3)
    try {
        for (x in listRemoval) {
            if (x == 1) listRemoval.removeAt(0)
        }
        println("list-removal: not-thrown " + listRemoval)
    } catch (e: ConcurrentModificationException) {
        println("list-removal: caught")
    }
}
