enum class Status(val code: Int) {
    OK(200)
}

fun main() {
    val s = Status.OK
    println(s.code)
}
