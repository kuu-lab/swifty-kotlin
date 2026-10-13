@file:OptIn(kotlin.js.ExperimentalJsReflectionCreateInstance::class)

import kotlin.reflect.KClass
import kotlin.reflect.createInstance

class ExportedBox(val value: Int = 7)

fun main() {
    val factory = KClass<ExportedBox>::createInstance
    val instance = factory(ExportedBox::class)
    println("${factory.name}:${instance.value}")
}
