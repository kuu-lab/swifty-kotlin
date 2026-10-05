open class Method(val value: String) {
    object Get : Method("GET")
    object Post : Method("POST")
    object Put : Method("PUT")

    companion object {
        fun parse(value: String): Method = when (value) {
            Get.value -> Get
            Post.value -> Post
            Put.value -> Put
            else -> Method(value)
        }
    }
}

class Holder(val method: Method)

fun supported(value: String): Boolean = when (value) {
    Method.Get.value, Method.Post.value -> true
    else -> false
}

fun instanceMatch(value: String, left: Method, right: Method): Int = when (value) {
    left.value -> 1
    right.value -> 2
    else -> 0
}

fun nestedMatch(value: String, left: Holder, right: Holder): Boolean = when (value) {
    left.method.value, right.method.value -> true
    else -> false
}

fun method(value: String): Method = Method(value)

fun expressionMatch(value: String): Boolean = when (value) {
    method("GET").value, method("POST").value -> true
    else -> false
}

object Counter {
    var count = 0
    fun next(): Int {
        count += 1
        return count
    }
}

fun callMatch(value: Int): Boolean = when (value) {
    Counter.next(), Counter.next() -> true
    else -> false
}

fun main() {
    println(Method.parse("GET") === Method.Get)
    println(Method.parse("POST") === Method.Post)
    println(Method.parse("PUT") === Method.Put)
    println(Method.parse("PATCH").value)
    println(supported("GET"))
    println(supported("POST"))
    println(supported("PUT"))
    println(instanceMatch("POST", Method.Get, Method.Post))
    println(instanceMatch("PUT", Method.Get, Method.Post))
    println(nestedMatch("POST", Holder(Method.Get), Holder(Method.Post)))
    println(nestedMatch("PUT", Holder(Method.Get), Holder(Method.Post)))
    println(expressionMatch("POST"))
    println(expressionMatch("PUT"))
    println(callMatch(2))
    println(Counter.count)
}
