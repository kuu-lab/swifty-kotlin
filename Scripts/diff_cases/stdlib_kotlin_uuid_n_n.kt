@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

@ExperimentalUuidApi
fun acceptUuid(uuid: Uuid): Uuid = uuid

fun main() {
    println(acceptUuid(Uuid.NIL).toString())
}
