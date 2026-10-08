@file:OptIn(kotlin.js.ExperimentalJsReflectionCreateInstance::class)
import kotlin.reflect.createInstance
fun main() {
    println((::createInstance).name)
}
