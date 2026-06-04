// SKIP-DIFF: kotlinc JVM startup exceeds 10s run timeout for script-style files
val x = 1 + 2
println(x)

val message = "Kotlin"
println(message.length)
println(message.uppercase())

val numbers = listOf(1, 2, 3, 4, 5)
println(numbers.sum())
println(numbers.filter { it % 2 == 0 })
