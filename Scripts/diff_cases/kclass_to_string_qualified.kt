// KUU-1080: Rendering uses the qualified name rather than the simple name hint.
package sample

class Annotated

fun main() {
    println(Annotated::class)
    println(Annotated::class.toString())
    println("class=${Annotated::class}")
    println(listOf(Annotated::class))
}
