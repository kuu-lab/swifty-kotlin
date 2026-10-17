@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kuu2589nullabilitynegative

import kotlinx.io.Buffer
import kotlinx.io.Segment

fun main() {
    val nonNull: Segment = Buffer().head
    println(nonNull)
}
