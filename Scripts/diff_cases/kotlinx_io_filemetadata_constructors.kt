import kotlinx.io.files.FileMetadata

// Direct probe for the FileMetadata.<init> default constructor contract.
private fun emit(label: String, metadata: FileMetadata) {
    println("FileMetadata.$label=${metadata.isRegularFile}:${metadata.isDirectory}:${metadata.size}")
}

fun main() {
    emit("explicit-positional", FileMetadata(true, false, 41L))
    emit("defaults", FileMetadata())
    emit("regular-only", FileMetadata(isRegularFile = true))
    emit("directory-only", FileMetadata(isDirectory = true))
    emit("size-only", FileMetadata(size = 41L))
    emit("regular-directory", FileMetadata(isRegularFile = true, isDirectory = true))
    emit("regular-size", FileMetadata(isRegularFile = true, size = 41L))
    emit("directory-size", FileMetadata(isDirectory = true, size = 41L))
}
