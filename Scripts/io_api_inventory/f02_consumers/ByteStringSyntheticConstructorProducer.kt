package f02constructorproducer

import kotlinx.io.bytestring.ByteString

fun constructorWithAllDefaults(data: ByteArray): ByteString = ByteString(data)

fun constructorWithDefaultEnd(data: ByteArray): ByteString = ByteString(data, 1)
