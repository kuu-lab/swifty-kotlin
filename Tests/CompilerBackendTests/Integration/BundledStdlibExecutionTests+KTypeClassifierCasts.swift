@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func kTypeClassifierKClassCasts(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("ktype_classifier_kclass_cast.kt", file: #filePath),
            expectedOutput: "java.io.Serializable\n",
            moduleName: "KUU1990ClassifierCast",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    @Test(arguments: [true, false])
    func kTypeClassifierKClassCastControls(fromArtifact: Bool) throws {
        let classifiers = ["java.io.Serializable", "kotlin.Any", "kotlin.String", "ClassifierBase", "kotlin.String"]
        let expected = classifiers.map { "true\ntrue\n" + String(repeating: $0 + "\n", count: 4) }.joined()
            + "false\nnull\nnull\nfalse\nnull\nClassCastException\nfalse\nClassCastException\n"
        try compileAndRunKotlin(
            try diffCaseSource("ktype_classifier_kclass_cast_controls.kt", file: #filePath),
            expectedOutput: expected,
            moduleName: "KUU1990ClassifierCastControls",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
