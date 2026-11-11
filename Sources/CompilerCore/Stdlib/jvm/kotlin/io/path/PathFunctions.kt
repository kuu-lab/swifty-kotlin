@file:kotlin.jvm.JvmName("PathsKt")
package kotlin.io.path

import java.nio.file.Path
import java.nio.file.Paths

@kotlin.internal.InlineOnly
public inline fun Path(path: String): Path = Paths.get(path)!!

@kotlin.internal.InlineOnly
public inline fun Path.absolute(): Path = this.toAbsolutePath()!!
