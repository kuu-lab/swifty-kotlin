@testable import CompilerCore
import Testing

@Suite
struct KotlinxIOPathSourceTests {
    @Test
    func testPathFactoriesPropertiesAndFileExceptionResolveFromBundledSource() throws {
        let source = """
        import kotlinx.io.files.Path
        import kotlinx.io.files.SystemPathSeparator
        import kotlinx.io.files.SystemTemporaryDirectory
        import kotlinx.io.files.FileNotFoundException

        fun simple(): Path = Path("/tmp/test")
        fun child(): Path = Path(Path("/tmp"), "a", "b")
        fun parentOf(path: Path): Path? = path.parent
        fun baseName(path: Path): String = path.name
        fun rooted(path: Path): Boolean = path.isAbsolute
        fun separator(): Char = SystemPathSeparator
        fun temporary(): Path = SystemTemporaryDirectory
        fun missing(): FileNotFoundException = FileNotFoundException("missing")
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        for name in ["Path", "FileNotFoundException"] {
            let symbol = try #require(sema.symbols.lookup(
                fqName: ["kotlinx", "io", "files", name].map { interner.intern($0) }
            ))
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
        }
    }
}
