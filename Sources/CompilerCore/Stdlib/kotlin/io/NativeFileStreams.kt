package kotlin.io

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Path
import java.nio.file.Paths
import kotlinx.io.asInputStream
import kotlinx.io.asOutputStream
import kotlinx.io.buffered
import kotlinx.io.files.Path as IoPath
import kotlinx.io.files.SystemFileSystem

public fun File.toPath(): Path = Paths.get(path)
public fun File.inputStream(): InputStream = SystemFileSystem.source(IoPath(path)).buffered().asInputStream()
public fun File.outputStream(): OutputStream = SystemFileSystem.sink(IoPath(path)).buffered().asOutputStream()
