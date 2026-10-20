open class CardDeck : ArrayList<String>()

class ShuffledDeck : CardDeck() {
    fun topCard(): String? = if (size > 0) get(0) else null
}

class SizedDeck(cap: Int) : ArrayList<String>(cap)

class CopyDeck(initial: Collection<String>) : ArrayList<String>(initial)

fun main() {
    val deck = CardDeck()
    println(deck.size)
    deck.add("Ace")
    deck.add("King")
    println(deck.size)
    println(deck[0])
    println(deck[1])

    val shuffled = ShuffledDeck()
    shuffled.addAll(deck)
    println(shuffled.size)
    println(shuffled.topCard())

    val sized = SizedDeck(10)
    sized.add("Queen")
    println(sized.size)
    println(sized[0])

    val copied = CopyDeck(deck)
    println(copied.size)
    println(copied[0])
    println(copied[1])
}
