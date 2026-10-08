@file:OptIn(kotlin.js.ExperimentalJsReflectionCreateInstance::class)

import kotlin.reflect.KClass
import kotlin.reflect.createInstance

var evaluations = 0
fun nextDefault(): Int { evaluations += 1; return 7 }

class ExportedBox(val value: Int = nextDefault())
class Empty
class Required(val value: Int)

fun main() {
    val bound = (ExportedBox::class)::createInstance
    val unbound = KClass<ExportedBox>::createInstance
    println("${bound.name}:${bound().value}:${unbound(ExportedBox::class).value}:$evaluations")
    println(Empty::class.createInstance()::class.simpleName)
    try {
        Required::class.createInstance()
        println("required:created")
    } catch (e: IllegalArgumentException) {
        println("required:${e.message}")
    }
}
