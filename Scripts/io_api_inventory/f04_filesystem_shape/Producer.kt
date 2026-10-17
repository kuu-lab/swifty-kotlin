package io.f04filesystem

import kotlinx.io.RawSink
import kotlinx.io.RawSource
import kotlinx.io.files.FileMetadata
import kotlinx.io.files.FileSystem
import kotlinx.io.files.Path

public fun roundTripFileSystem(fileSystem: FileSystem): FileSystem = fileSystem

@Suppress("UNUSED_VARIABLE")
public fun compilePublicMemberSurface(
    fileSystem: FileSystem,
    path: Path,
    destination: Path,
): FileSystem {
    val exists: Boolean = fileSystem.exists(path)
    fileSystem.delete(path)
    fileSystem.createDirectories(destination)
    fileSystem.atomicMove(path, destination)
    val source: RawSource = fileSystem.source(path)
    val sink: RawSink = fileSystem.sink(path)
    val metadata: FileMetadata? = fileSystem.metadataOrNull(path)
    val resolved: Path = fileSystem.resolve(path)
    val children: Collection<Path> = fileSystem.list(path)
    return fileSystem
}
