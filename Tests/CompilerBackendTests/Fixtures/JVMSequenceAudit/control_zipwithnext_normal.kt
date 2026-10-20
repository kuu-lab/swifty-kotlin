fun main() {
println(sequenceOf(1, 2, 3).zipWithNext { a, b -> "$a:$b" }.toList())
println(sequenceOf(1, 2, 3).zipWithNext { a, b -> null as String? }.toList())
}
