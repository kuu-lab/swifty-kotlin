package io.gate.bytestring

import kotlinx.io.bytestring.ByteStringBuilder

fun retainBuilderType(value: ByteStringBuilder): ByteStringBuilder = value

fun main() {
    println("BYTESTRINGBUILDER_CLASS_SHAPE_PASS")
}
