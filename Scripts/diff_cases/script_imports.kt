// SKIP-DIFF: kotlinc JVM startup exceeds 10s run timeout for script-style files
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

val x = -5
val y = 3
println(abs(x))
println(max(x, y))
println(min(x, y))
