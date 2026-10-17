package kotlinx.io.files

// This same-package implementation is compiled as a separate module against
// the candidate .kklib to check that the sealed flag survives export.
class ExternalFileSystem : FileSystem by SystemFileSystem

fun main() {
    println("external implementation unexpectedly compiled")
}
