import Testing

@Suite
struct IOPathExtensionsTests {
    @Test
    func pathOperationsCompileWithBundledArtifact() throws {
        try assertKotlinCompilesToObject(
            """
            import kotlinx.io.files.*

            fun main() {
                val path = Path("/a/b/c.txt")
                println(Path("/").isRoot)
                println(Path("relative").isRelative)
                println(path / "d.txt")
                println(path.resolve("d.txt"))
                println(Path("/a/x/../b").normalize())
                println(path.relativeTo(Path("/a")))
                println(path.startsWith(Path("/a/b")))
                println(path.endsWith("c.txt"))
                println(Path("archive.tar.gz").nameWithoutExtension)
                println(Path("a/../../b").normalize())
                println(Path("/../../a").normalize())
                println(Path("/a").resolve(Path("/x")))
            }
            """,
            moduleName: "IOPathExtensionsTest"
        )
    }
}
