class Test<T: Char>(val k: T) {
    fun test(): String {
        fun nested(x: T = k): String = "O$x"
        return nested()
    }
}

fun main() {
    println(Test('K').test())
}
