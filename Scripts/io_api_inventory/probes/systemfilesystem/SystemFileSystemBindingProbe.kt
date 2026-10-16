import kotlinx.io.files.FileSystem
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem

fun systemFileSystemBinding() {
    val first: FileSystem = SystemFileSystem
    val second: FileSystem = SystemFileSystem

    check(first === second) { "SystemFileSystem must return the same platform value" }
    check(first.exists(Path("."))) { "SystemFileSystem must address the current directory" }

    println("SystemFileSystem:type=FileSystem")
    println("SystemFileSystem:identity=stable")
    println("SystemFileSystem:current-directory-exists=true")
}

fun main() = systemFileSystemBinding()
