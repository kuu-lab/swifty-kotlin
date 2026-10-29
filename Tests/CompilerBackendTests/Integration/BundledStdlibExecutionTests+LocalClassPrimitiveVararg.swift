@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false], ["O0", "O2"])
    func testLocalClassPrimitiveVarargProperties(allowDefaultStdlibLibrary: Bool, optimization: String) throws {
        try compileAndRunKotlin(
            try diffCaseSource("local_class_primitive_vararg_property.kt", file: #filePath),
            expectedOutput: [
                "true\nfalse\n0\n2\n", // Boolean
                String(repeating: "1\n2\n0\n2\n", count: 4), // Byte, Short, Int, Long
                "a\nb\n0\n2\n", // Char
                String(repeating: "1.5\n2.5\n0\n2\n", count: 2), // Float, Double
                String(repeating: "1\n2\n0\n2\n", count: 4), // Unsigned primitives
                "5\n7\ny\nnull\n9\n", // Aliases, mutable storage, reference and nullable controls
            ].joined(),
            moduleName: "KUU2144LocalClassPrimitiveVararg",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: optimization == "O0" ? .O0 : .O2,
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
