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

    @Test(arguments: [
        "isNaN(0.0)",
        "isInfinite(0.0)",
        "isFinite(0.0)",
        "compare(1.0, 2.0)",
        "signum(-1.5)",
        "sum(1.0, 2.0)",
        "min(1.0, 2.0)",
        "max(1.0, 2.0)",
        "parseDouble(\"1.0\")",
        "toString(1.0)",
    ])
    func kotlinDoubleDoesNotExposeJavaLangStaticMethods(_ call: String) throws {
        let source = "fun probe() = Double.\(call)"
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: false)
            try runSema(context)
            #expect(context.diagnostics.hasError, "Expected Double.\(call) to be rejected")
        }
    }

    @Test
    func javaLangDoubleStaticMethodsRemainAvailable() throws {
        let source = """
        fun isNaN(): Boolean = java.lang.Double.isNaN(0.0)
        fun isInfinite(): Boolean = java.lang.Double.isInfinite(0.0)
        fun isFinite(): Boolean = java.lang.Double.isFinite(0.0)
        fun compare(): Int = java.lang.Double.compare(1.0, 2.0)
        fun signum(): Double = java.lang.Double.signum(-1.5)
        fun sum(): Double = java.lang.Double.sum(1.0, 2.0)
        fun min(): Double = java.lang.Double.min(1.0, 2.0)
        fun max(): Double = java.lang.Double.max(1.0, 2.0)
        fun parseDouble(): Double = java.lang.Double.parseDouble("1.0")
        fun toString(): String = java.lang.Double.toString(1.0)
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], allowDefaultStdlibLibrary: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }
}
