import design_patterns.*
fun main() {
    val store = FoodStore(OnlyChocolateFilterStrategy())
    println(store.foodItems().map { it.title }.joinToString("|"))
    store.changeStrategy(PriceFilterStrategy(4))
    println(store.foodItems().map { it.title }.joinToString("|"))
    store.changeStrategy(SearchWordFilterStrategy("lays"))
    println(store.foodItems().size)
}
