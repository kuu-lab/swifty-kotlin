package io2624producer

import kotlinx.io.bytestring.ByteString

fun toByteArrayAllDefaults(value: ByteString): ByteArray = value.toByteArray()
fun toByteArrayDefaultStart(value: ByteString): ByteArray = value.toByteArray(endIndex = 3)
fun toByteArrayDefaultEnd(value: ByteString): ByteArray = value.toByteArray(startIndex = 3)
fun toByteArrayExplicit(value: ByteString): ByteArray = value.toByteArray(startIndex = 1, endIndex = 4)

fun substringDefaultEnd(value: ByteString): ByteString = value.substring(startIndex = 2)
fun substringExplicit(value: ByteString): ByteString = value.substring(startIndex = 1, endIndex = 4)

fun copyIntoAllDefaults(value: ByteString, destination: ByteArray) = value.copyInto(destination)
fun copyIntoDefaultOffset(value: ByteString, destination: ByteArray) =
    value.copyInto(destination, startIndex = 2, endIndex = 4)
fun copyIntoDefaultStart(value: ByteString, destination: ByteArray) =
    value.copyInto(destination, destinationOffset = 2, endIndex = 4)
fun copyIntoDefaultEnd(value: ByteString, destination: ByteArray) =
    value.copyInto(destination, destinationOffset = 1, startIndex = 3)
