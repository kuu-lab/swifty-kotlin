fun retLambda(flag: Boolean): (String) -> String = if (flag) { s -> s.uppercase() } else { s -> s.lowercase() }
fun pick(flag: Boolean): (Int) -> Int = when (flag) { true -> { x -> x + 1 }; false -> { x -> x - 1 } }

fun main() {
    println(retLambda(true)("Ab"))
    println(retLambda(false)("Ab"))
    val sel: (Boolean) -> ((Int) -> Int) = { b -> if (b) { x -> x + 1 } else { x -> x - 1 } }
    println(sel(true)(10))
    println(sel(false)(10))
    println(pick(true)(10))
    println(pick(false)(10))
}
