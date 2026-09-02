fun main() {
    val count = 100000
    val map = mutableMapOf<Int, Int>()
    val set = mutableSetOf<Int>()

    var value = 0
    while (value < count) {
        map[value] = value * 3
        set.add(value)
        value++
    }

    // Updating an existing key must keep its original position.
    map[0] = -1
    set.add(0)

    var checksum = 0
    value = 0
    while (value < count) {
        if (value % 997 == 0) {
            checksum += map[value] ?: 0
            if (set.contains(value)) checksum++
        }
        value++
    }

    println("${map.size},${set.size},${map[0]},${map.keys.first()},${map.keys.last()},${set.first()},${set.last()},$checksum")
}
