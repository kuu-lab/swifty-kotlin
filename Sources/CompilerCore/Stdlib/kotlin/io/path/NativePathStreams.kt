package kotlin.io.path

import java.io.InputStream
import kotlin.internal.KsSymbolName
import kotlinx.io.asInputStream
import kotlinx.io.buffered
import kotlinx.io.files.Path as IoPath
import kotlinx.io.files.SystemFileSystem

public fun Path.createFile(): Path {
    createNativeFile(toString())
    return this
}
public fun Path.inputStream(): InputStream = SystemFileSystem.source(IoPath(toString())).buffered().asInputStream()

@KsSymbolName("__kk_native_nio_create_file")
private external fun createNativeFile(path: String)
