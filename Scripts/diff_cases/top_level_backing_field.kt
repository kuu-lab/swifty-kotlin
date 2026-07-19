var doubled: Int = 5
    get() = field * 2

var lazyCache: Int? = null
    get() {
        if (field == null) {
            field = 999
        }
        return field
    }

var counter: Int = 0
    get() {
        field += 1
        return field
    }

fun main() {
    println(doubled)
    println(doubled)
    println(lazyCache)
    println(lazyCache)
    println(counter)
    println(counter)
    println(counter)
}
