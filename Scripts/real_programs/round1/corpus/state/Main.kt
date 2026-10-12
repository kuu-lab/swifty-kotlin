import design_patterns.*
fun main() {
    val machine = CocaColaMachine()
    repeat(3) { println(machine.insertDollar()); println(machine.pressButton()) }
    println(machine.currentState)
    println(machine.insertDollar())
}
