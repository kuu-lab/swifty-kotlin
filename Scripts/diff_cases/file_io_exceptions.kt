import java.io.File

// KSP-619 / BUG-016: kotlin.io filesystem exceptions must be catchable by type
// (both the concrete class and the FileSystemException base) and expose
// file / other / reason, whether they are raised by the runtime (File.copyTo)
// or constructed in Kotlin.
fun main() {
    val base = File("/tmp/kswiftk_file_io_exceptions")
    val src = File("/tmp/kswiftk_file_io_exceptions/src.txt")
    val dst = File("/tmp/kswiftk_file_io_exceptions/dst.txt")
    src.delete()
    dst.delete()
    base.delete()
    base.mkdirs()
    src.writeText("hello")
    dst.writeText("existing")

    // Runtime-raised FileAlreadyExistsException, caught by its own type.
    try {
        src.copyTo(dst)
        println("not thrown")
    } catch (e: FileAlreadyExistsException) {
        println("caught FileAlreadyExistsException")
        println(e.message)
        println(e.file.path)
        println(e.other?.path)
        println(e.reason)
    }

    // A sibling type must not swallow it; the ordered catch picks the right clause.
    try {
        src.copyTo(dst)
    } catch (e: NoSuchFileException) {
        println("wrong: NoSuchFileException")
    } catch (e: FileAlreadyExistsException) {
        println("ordered catch picked FileAlreadyExistsException")
    }

    // The base type catches derived exceptions.
    try {
        src.copyTo(dst)
    } catch (e: FileSystemException) {
        println("caught as FileSystemException")
    }

    // Runtime-raised NoSuchFileException.
    try {
        File("/tmp/kswiftk_file_io_exceptions/missing.txt")
            .copyTo(File("/tmp/kswiftk_file_io_exceptions/out.txt"))
    } catch (e: NoSuchFileException) {
        println("caught NoSuchFileException")
        println(e.message)
    }

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

    src.delete()
    dst.delete()
    base.delete()
    println(base.exists())
}
