// KUU-2006: A single component is still a destructuring lambda parameter.
fun main() {
    val transform: (List<Int>) -> Int = { (a) -> a }
    println(transform(listOf(7, 8)))
}
