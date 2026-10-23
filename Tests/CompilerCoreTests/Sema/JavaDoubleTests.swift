@testable import CompilerCore
import Testing

@Suite
struct JavaDoubleTests {
    @Test
    func positiveInfinityUsesTheKotlinDoubleType() throws {
        let source = """
        fun kotlinInfinity(): Double = Double.POSITIVE_INFINITY
        fun javaInfinity(): Double = java.lang.Double.POSITIVE_INFINITY
        fun sameInfinity(): Boolean = kotlinInfinity() == javaInfinity()
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")

            let sema = try #require(context.sema)
            let javaDoublePath = ["java", "lang", "Double"].map(context.interner.intern)
            let javaDouble = try #require(sema.symbols.lookup(fqName: javaDoublePath))
            #expect(sema.symbols.symbol(javaDouble)?.kind == .class)
        }
    }
}
