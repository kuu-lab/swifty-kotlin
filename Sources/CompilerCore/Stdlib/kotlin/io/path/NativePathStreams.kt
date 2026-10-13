package kotlin.io.path

import java.io.InputStream
import java.nio.file.Path
import kotlin.internal.KsSymbolName
import kotlinx.io.asInputStream
import kotlinx.io.buffered
import kotlinx.io.files.Path as IoPath
import kotlinx.io.files.SystemFileSystem

// Minimal Native producers used by the locked NioTest file-channel cases.
// The attribute/open-option overloads remain outside this producer subset.
public fun Path.createFile(): Path {
    createNativeFile(toString())
    return this
}
public fun Path.inputStream(): InputStream = SystemFileSystem.source(IoPath(toString())).buffered().asInputStream()

@KsSymbolName("__kk_native_nio_create_file")
private external fun createNativeFile(path: String)
