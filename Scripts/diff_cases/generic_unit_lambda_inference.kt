// KSP-677: a generic higher-order function `fun <T> f(action: () -> T): T` must infer T
// from the lambda body, including a Unit-valued body. Previously the unresolved type
// parameter was pushed down as the lambda body's expected type, so a Unit-bodied lambda
// produced an error type and failed inference (KSWIFTK-TYPE-0001 / KSWIFTK-SEMA-0002).
class Box(val label: String)

fun <T> Box.transform(action: () -> T): T = action()

fun main() {
    val b = Box("box")
    b.transform { println("unit body: ${b.label}") }
    val doubled: Int = b.transform { 21 * 2 }
    val text: String = b.transform { "value body" }
    b.transform {
        println("doubled=$doubled")
        println("text=$text")
    }
}
