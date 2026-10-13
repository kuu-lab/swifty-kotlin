// KUU-1870: Keep Day07.calculateIdentity's companion collection fold seed intact.
class Day07 {
    private class Hand {
        private fun calculateIdentity(
            cards: String,
            strength: String,
            categoryCalculation: (String) -> List<Int>
        ): Int {
            val category = categoryCalculation(cards)
            return cards.fold(CATEGORIES.indexOf(category)) { acc, card -> (acc shl 4) or strength.indexOf(card) }
        }

        fun run(): Int = calculateIdentity("AA", "A") { listOf(2) }

        companion object {
            private val CATEGORIES = listOf(listOf(1, 1), listOf(2))
        }
    }

    fun run(): Int = Hand().run()
}

fun main() {
    println(Day07().run())
}
