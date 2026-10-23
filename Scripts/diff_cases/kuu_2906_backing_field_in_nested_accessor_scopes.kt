// KUU-2906: Backing-field references stay bound to the accessor through nested scopes.
fun <T> eval(fn: () -> T) = fn()

val lambda: String = "O"
    get() = eval { field } + "K"

abstract class Your {
    abstract val your: String
    fun foo() = your
}

val fieldInsideField: String = "O"
    get() = field + object : Your() {
        override val your = "K"
            get() = field
    }.foo()

val fieldInsideNested: String = "O"
    get() = object : Your() {
        override val your = field
    }.foo() + "K"

class My {
    var my: String = "U"
        get() = eval { field }
        set(arg) {
            class Local {
                fun foo() {
                    field = arg + "K"
                }
            }
            Local().foo()
        }
}

fun main() {
    println(lambda)
    println(fieldInsideField)
    println(fieldInsideNested)
    val my = My()
    my.my = "O"
    println(my.my)
}
