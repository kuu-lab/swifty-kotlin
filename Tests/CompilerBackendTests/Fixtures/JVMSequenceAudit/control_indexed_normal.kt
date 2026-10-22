fun main() {
println(sequenceOf(10, 20).mapIndexed { index, value -> "$index:$value" }.toList())
println(sequenceOf(10, 20).onEachIndexed { index, value -> println("$index:$value") }.toList())
println(sequenceOf(10, 20).mapIndexedNotNull { index, value -> if (index == 0) null else "$index:$value" }.toList())
println(sequenceOf(10, 20).filterIndexed { index, value -> index == 1 }.toList())
}
