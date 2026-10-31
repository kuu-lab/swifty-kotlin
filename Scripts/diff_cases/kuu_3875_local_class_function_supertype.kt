// KUU-3875: a local class implementing a FunctionN interface — or declaring
// an `operator invoke` member at all — must still construct via `C()`. The
// invoke convention applies to instances, not to the class name.
fun main() {
    class Nominal : Function0<Int> {
        override fun invoke(): Int = 42
    }
    println(Nominal().invoke())
    println(Nominal()())

    class FnType : () -> Int {
        override fun invoke(): Int = 7
    }
    println(FnType().invoke())

    class Unary : (Int) -> String {
        override fun invoke(value: Int): String = "v$value"
    }
    println(Unary().invoke(5))

    class OperatorOnly {
        operator fun invoke(): Int = 9
    }
    println(OperatorOnly()())
}
