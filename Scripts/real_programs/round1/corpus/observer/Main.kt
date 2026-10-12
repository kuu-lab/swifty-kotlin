import design_patterns.*
fun main() {
    val list = PonyList()
    val observer = PonyObserver { println(it.joinToString(",")) }
    list.addObserver(observer)
    list.add("Twilight")
    list.add("Rainbow")
    list.removeObserver(observer)
    list.add("Pinkie")
}
