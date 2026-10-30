// KUU-3838: a function type may be an object literal's delegation specifier;
// it maps to the FunctionN interface like a named-class supertype.
fun main() {
    val o: () -> Int = object : () -> Int {
        override fun invoke(): Int = 42
    }
    println(o())
    val p: (Int) -> String = object : (Int) -> String {
        override fun invoke(value: Int): String = "v$value"
    }
    println(p(7))
}
