// KUU-3788: a property with an explicit getter must evaluate the getter at
// run time instead of folding to its backing initializer (JetBrains
// properties/fieldInsideField.kt, fieldInsideLambda.kt, fieldInsideNested.kt).

fun <T> eval(fn: () -> T) = fn()

abstract class Your {
    abstract val your: String
    fun foo() = your
}

val fieldInsideField: String = "O"
    get() = field + object : Your() {
        override val your = "K"
            get() = field
    }.foo()

val fieldInsideLambda: String = "O"
    get() = eval { field } + "K"

val fieldInsideNested: String = "O"
    get() = object : Your() {
        override val your = field
    }.foo() + "K"

fun main() {
    println(fieldInsideField)
    println(fieldInsideLambda)
    println(fieldInsideNested)
}
