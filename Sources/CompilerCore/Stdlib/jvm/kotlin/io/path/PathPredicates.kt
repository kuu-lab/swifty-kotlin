@file:kotlin.jvm.JvmName("PathsKt")
package kotlin.io.path

import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path

public fun Path.isRegularFile(vararg options: LinkOption): Boolean = Files.isRegularFile(this, *options)

public fun Path.notExists(vararg options: LinkOption): Boolean = Files.notExists(this, *options)
