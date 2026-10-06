// SKIP-DIFF (DEBT-DIFF-001): kotlin.reflect.AssociatedObjectKey / ExperimentalAssociatedObjects
// do not resolve in the JVM kotlinc reference environment.
import kotlin.reflect.AssociatedObjectKey
import kotlin.reflect.ExperimentalAssociatedObjects

@OptIn(ExperimentalAssociatedObjects::class)
@AssociatedObjectKey
annotation class Binding

fun main() {
    println("ok")
}
