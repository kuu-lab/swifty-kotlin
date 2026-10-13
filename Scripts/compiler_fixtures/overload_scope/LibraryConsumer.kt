import collisioncontract.*
fun Collision.consumerGate(): String = gate(true) { "message" }
fun Collision.consumerWidth() {
    val values: Map<Long, Int> = mapOf(0L to 1)
    values.forEach { (number, length) -> println(width(number)) }
}
fun main() {
    val reader: ChildReader = Reader()
    println(reader.read("consumer", 2))
    println(Collision().consumerGate())
    Collision().consumerWidth()
    Priority().check()
    ExtensionFallback().check()
    Outer().Inner().check()
}
