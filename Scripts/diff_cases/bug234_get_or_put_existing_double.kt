fun main() {
    val fromPairs = mutableMapOf("pair" to 2.5)
    println(fromPairs.getOrPut("pair") { 9.5 })

    val fromAssignment = mutableMapOf<String, Double>()
    fromAssignment["assigned"] = 3.25
    println(fromAssignment.getOrPut("assigned") { 9.5 })
}
