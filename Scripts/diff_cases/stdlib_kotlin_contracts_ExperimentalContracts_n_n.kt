@file:OptIn(kotlin.contracts.ExperimentalContracts::class)

import kotlin.contracts.ExperimentalContracts

@ExperimentalContracts
fun experimentalContractsUse() {}

fun main() {
    experimentalContractsUse()
    println("ExperimentalContracts")
}
