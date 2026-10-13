class Search(private val goal: Int) {
    fun traverse(next: (Int) -> List<Pair<Int, Int>>): Int {
        var best = 0
        val visited = mutableSetOf<Int>()
        fun walk(place: Int, steps: Int): Int {
            if (place == goal) {
                best = maxOf(steps, best)
                return best
            }
            visited += place
            next(place).filter { (p, _) -> p !in visited }
                .forEach { (p, distance) -> walk(p, distance + steps) }
            visited -= place
            return best
        }
        return walk(0, 0)
    }
}

fun main() {
    println(Search(2).traverse { place -> if (place < 2) listOf(place + 1 to 1) else emptyList() })
}
