@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func objectAndCompanionCustomAccessorIncDecMatchReference() throws {
        try compileAndRunKotlin(
            try diffCaseSource("object_companion_custom_accessor_incdec.kt", file: #filePath),
            expectedOutput: try diffCaseSource("object_companion_custom_accessor_incdec.expected", file: #filePath),
            moduleName: "KUU2860ObjectCompanionAccessorIncDec",
            allowDefaultStdlibLibrary: true,
            expectedStderr: ""
        )
    }
}
