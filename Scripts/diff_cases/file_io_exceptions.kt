import java.io.File

// KSP-619 / BUG-016: kotlin.io filesystem exceptions must be catchable by type
// (both the concrete class and the FileSystemException base) and expose
// file / other / reason when constructed directly in Kotlin.
//
// CLEANUP-STUB-107 removed File.copyTo, so the runtime-raised half of this
// coverage (FileAlreadyExistsException / NoSuchFileException thrown by
// File.copyTo) no longer applies; only the Kotlin-constructed cases below
// remain exercisable.
fun main() {
    val src = File("/tmp/kswiftk_file_io_exceptions/src.txt")
    val dst = File("/tmp/kswiftk_file_io_exceptions/dst.txt")

    // Kotlin-constructed AccessDeniedException, caught through the base type.
    try {
        throw AccessDeniedException(src, dst, "permission denied")
    } catch (e: FileSystemException) {
        println("caught AccessDeniedException as FileSystemException")
        println(e.message)
    }

    // A non-matching catch clause lets the exception propagate.
    try {
        try {
            throw AccessDeniedException(src)
        } catch (e: FileAlreadyExistsException) {
            println("wrong: AccessDeniedException caught as FileAlreadyExistsException")
        }
    } catch (e: AccessDeniedException) {
        println("propagated to outer AccessDeniedException")
        println(e.message)
        println(e.file.path)
        println(e.other)
        println(e.reason)
    }
}
