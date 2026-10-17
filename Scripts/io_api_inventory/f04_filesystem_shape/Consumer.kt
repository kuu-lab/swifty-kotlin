package io.f04filesystem.consumer

import io.f04filesystem.roundTripFileSystem
import kotlinx.io.files.FileSystem
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem

fun main() {
    val fileSystem: FileSystem = roundTripFileSystem(SystemFileSystem)
    if (!fileSystem.exists(Path("."))) error("current directory should exist")
    println("FileSystem exported consumer: ok")
}
