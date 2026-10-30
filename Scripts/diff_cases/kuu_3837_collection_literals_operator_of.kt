// KOTLINC_FLAGS: -Xcollection-literals
class MyList(val data: String) {
    companion object {
        operator fun of(vararg items: String) = MyList(items.joinToString(","))
        operator fun of(first: String, second: String) = MyList("$first-$second")
    }
}

fun main() {
    println(MyList.of("a", "b", "c").data)
    println(MyList.of("a", "b").data)
    println(MyList.of().data)
}
