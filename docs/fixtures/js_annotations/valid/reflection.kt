@file:OptIn(kotlin.js.ExperimentalJsReflectionCreateInstance::class)

import kotlin.reflect.createInstance

var defaultEvaluationCount = 0
fun nextDefault(): Int { defaultEvaluationCount += 1; return 40 + defaultEvaluationCount }

class ExportedBox(val value: Int = 7)
class Empty
class SideEffectDefault(val value: Int = nextDefault())
class RequiredConstructor(val value: Int)
class MultipleEligibleConstructors(val value: Int = 7) {
    constructor() : this(42)
}

fun main() {
    println("${ExportedBox::class.simpleName}:${ExportedBox::class.createInstance().value}:$defaultEvaluationCount")
    println(Empty::class.createInstance()::class.simpleName)
    val firstDefault = SideEffectDefault::class.createInstance()
    println("default:${firstDefault.value}:$defaultEvaluationCount")
    val secondDefault = SideEffectDefault::class.createInstance()
    println("default:${secondDefault.value}:$defaultEvaluationCount")
    try {
        RequiredConstructor::class.createInstance()
        println("required:created")
    } catch (e: IllegalArgumentException) {
        println("required:${e.message}")
    }
    try {
        MultipleEligibleConstructors::class.createInstance()
        println("multiple:created")
    } catch (e: IllegalArgumentException) {
        println("multiple:${e.message}")
    }
}
