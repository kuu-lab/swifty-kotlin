// CANDIDATE-ONLY: kotlin.reflect.AssociatedObjectKey / ExperimentalAssociatedObjects are not
// available in the JVM kotlinc reference surface; this fixture only declares the key annotation.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: reflect_associated_object_key.expected.stdout
import kotlin.reflect.AssociatedObjectKey
import kotlin.reflect.ExperimentalAssociatedObjects

@OptIn(ExperimentalAssociatedObjects::class)
@AssociatedObjectKey
annotation class Binding

fun main() {
    println("ok")
}
