fun main() {
    for (iv in "hello".withIndex()) {
        println(iv)
    }

    for (iv in "".withIndex()) {
        println(iv)
    }
    println("done")
}
