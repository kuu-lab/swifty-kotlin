#if canImport(Testing)
import Testing

@Suite struct KotlinCompilationFileIOTests {
    // STDLIB-IO-PROP-002: `File.extension` resolves to a non-null `String`
    // through the Kotlin-source-backed extension property declared in
    // `Stdlib/kotlin/io/Files.kt` (CLEANUP-STUB-107 removed the old synthetic
    // stub file this comment used to point at).
    // The property is exposed as a member so that callers can use it on any
    // `java.io.File` instance produced by either `File(path)` constructor.
    @Test func testCompile_file_extensionPropertyResolves() throws {
        try assertKotlinCompilesToKIR("""
        import java.io.File

        fun main() {
            val src = File("Main.kt")
            val archive = File("archive.tar.gz")
            val readme = File("README")
            val nested = File("/tmp", "notes.md")
            val srcExt: String = src.extension
            val archiveExt: String = archive.extension
            val readmeExt: String = readme.extension
            val nestedExt: String = nested.extension
            println(srcExt)
            println(archiveExt)
            println(readmeExt)
            println(nestedExt)
        }
        """)
    }

    // STDLIB-IO-PROP-004: `File.isRooted` compiles end-to-end through Sema to KIR.
    // The property is registered in the `kotlin.io` package with `java.io.File` as
    // the receiver and is backed by the runtime helper `kk_file_isRooted`.
    @Test func testCompile_file_isRootedPropertyResolves() throws {
        try assertKotlinCompilesToKIR("""
        import java.io.File

        fun main() {
            val abs = File("/tmp/demo")
            val rel = File("relative/path")
            val absRooted: Boolean = abs.isRooted
            val relRooted: Boolean = rel.isRooted
            println(absRooted)
            println(relRooted)
        }
        """)
    }

    // STDLIB-IO-PROP-003: `File.invariantSeparatorsPath` compiles through
    // Sema → KIR with explicit kotlin.io import.
    @Test func testCompile_file_invariantSeparatorsPathPropertyResolves() throws {
        try assertKotlinCompilesToKIR("""
        import java.io.File
        import kotlin.io.invariantSeparatorsPath

        fun normalize(file: File): String {
            return file.invariantSeparatorsPath
        }
        """)
    }
}
#endif
