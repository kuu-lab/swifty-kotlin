package kotlin.io

import java.io.File

// MIGRATION-IO-001: File read/write extensions

public fun File.readText(): String = this.__kk_file_readText()

public fun File.writeText(text: String): Unit = this.__kk_file_writeText(text)

public fun File.appendText(text: String): Unit = this.__kk_file_appendText(text)

public fun File.readBytes() = this.__kk_file_readBytes()

public fun File.writeBytes(array: ByteArray): Unit = this.__kk_file_writeBytes(array)

public fun File.appendBytes(array: ByteArray): Unit = this.__kk_file_appendBytes(array)
