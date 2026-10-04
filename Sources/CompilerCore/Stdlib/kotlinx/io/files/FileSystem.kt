/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 *
 * Derived from kotlinx-io core/common/src/files/FileSystem.kt (tag 0.9.1).
 */
package kotlinx.io.files

import kotlin.internal.KsSymbolName

public interface FileSystem {
    public fun exists(path: Path): Boolean
    public fun delete(path: Path, mustExist: Boolean = true)
    public fun createDirectories(path: Path, mustCreate: Boolean = false)
    public fun atomicMove(source: Path, destination: Path)
    public fun metadataOrNull(path: Path): FileMetadata?
    public fun resolve(path: Path): Path
    public fun list(directory: Path): Collection<Path>
}

public object SystemFileSystem : FileSystem {
    override fun exists(path: Path): Boolean = ioFsExists(path.toString())

    override fun delete(path: Path, mustExist: Boolean) {
        ioFsDelete(path.toString(), mustExist)
    }

    override fun createDirectories(path: Path, mustCreate: Boolean) {
        ioFsCreateDirectories(path.toString(), mustCreate)
    }

    override fun atomicMove(source: Path, destination: Path) {
        ioFsAtomicMove(source.toString(), destination.toString())
    }

    override fun metadataOrNull(path: Path): FileMetadata? {
        val fields = ioFsMetadata(path.toString()) ?: return null
        return FileMetadata(fields[0] != 0L, fields[1] != 0L, fields[2])
    }

    override fun resolve(path: Path): Path = Path(ioFsResolve(path.toString()))

    override fun list(directory: Path): Collection<Path> {
        val result = mutableListOf<Path>()
        for (name in ioFsList(directory.toString())) {
            result.add(Path(directory, name))
        }
        return result
    }
}

public class FileMetadata(
    public val isRegularFile: Boolean = false,
    public val isDirectory: Boolean = false,
    public val size: Long = 0L
)

@KsSymbolName("__kk_io_fs_exists")
private external fun ioFsExists(path: String): Boolean

@KsSymbolName("__kk_io_fs_delete")
private external fun ioFsDelete(path: String, mustExist: Boolean)

@KsSymbolName("__kk_io_fs_create_directories")
private external fun ioFsCreateDirectories(path: String, mustCreate: Boolean)

@KsSymbolName("__kk_io_fs_atomic_move")
private external fun ioFsAtomicMove(source: String, destination: String)

@KsSymbolName("__kk_io_fs_metadata")
private external fun ioFsMetadata(path: String): LongArray?

@KsSymbolName("__kk_io_fs_list")
private external fun ioFsList(path: String): List<String>

@KsSymbolName("__kk_io_fs_resolve")
private external fun ioFsResolve(path: String): String
