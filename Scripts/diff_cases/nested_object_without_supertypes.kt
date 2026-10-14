class Bag {
    object M {
        val m = 5
    }
}

fun useNested() = Bag.M.m

fun main() {
    println(useNested())
}
