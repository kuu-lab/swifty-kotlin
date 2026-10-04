import kotlin.uuid.ExperimentalUuidApi

fun main() {
    val marker = ExperimentalUuidApi()
    println(marker is Annotation)
}
