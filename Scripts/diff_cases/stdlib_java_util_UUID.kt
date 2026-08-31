@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import java.util.UUID
import kotlin.uuid.toKotlinUuid

fun main() {
    val javaUuid = UUID(
        0x0102030405060708L,
        0x090a0b0c0d0e0f10L,
    )
    val kotlinUuid = javaUuid.toKotlinUuid()

    println("java UUID shell constructed: true")
    println("toKotlinUuid preserves bits: ${kotlinUuid.toString() == "01020304-0506-0708-090a-0b0c0d0e0f10"}")
}
