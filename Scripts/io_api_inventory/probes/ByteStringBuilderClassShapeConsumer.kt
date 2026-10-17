package io.gate.bytestring.consumer

import io.gate.bytestring.producer.passBuilderThrough
import kotlinx.io.bytestring.ByteStringBuilder

fun main() {
    passBuilderThrough(ByteStringBuilder())
    println("BYTESTRINGBUILDER_CLASS_SHAPE_PASS")
}
