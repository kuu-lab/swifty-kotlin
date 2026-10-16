package io.bytestring.shape.negative

import kotlinx.io.bytestring.ByteString

class ByteStringSubclassProbe : ByteString(byteArrayOf())
class ByteStringCompanionSubclassProbe : ByteString.Companion

fun main() {}
