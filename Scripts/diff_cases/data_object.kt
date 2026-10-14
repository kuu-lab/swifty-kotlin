data object None {
    data object Inner
}

fun main() {
    println(None)
    println(None == None)
    println(None.toString())
    println(None.hashCode() == None.hashCode())
    println(None.hashCode() != None.Inner.hashCode())
    println(None.hashCode() != 0)
    println(None.Inner.hashCode() != 0)
}
