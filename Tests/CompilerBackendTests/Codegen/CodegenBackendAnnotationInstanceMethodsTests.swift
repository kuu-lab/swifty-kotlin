@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendAnnotationInstanceMethodsTests {
    @Test(arguments: [true, false])
    func annotationMethodsMatchJVM(useArtifact: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/annotation_instance_methods.kt"
        ), encoding: .utf8)
        // Captured from the Kotlin/JVM reference implementation.
        let expected = """
        true
        false
        true
        false
        @annotationmethods.B4(s=x)
        true
        false
        false
        true
        13334
        13309
        @annotationmethods.B2(a=[1, 2])
        true
        true
        false
        false
        @annotationmethods.B1(i=1)
        annotation=@annotationmethods.B1(i=1)
        true
        true
        true
        false
        false
        @annotationmethods.Empty()
        0
        @annotationmethods.Mixed(z=default, a=7)
        true
        1544821471
        true
        false
        @annotationmethods.Nested(b=@annotationmethods.B1(i=3), names=[x, y])
        397402884
        true
        false
        true
        true
        -2147418244
        2139160486
        @annotationmethods.Numbers(f=1.0, d=2.0, b=true, c=a, l=42)
        2139160513
        @annotationmethods.Arrays(b=[true, false], c=[a, b], d=[1.0, 2.0])
        true
        true
        false
        """ + "\n"
        try assertKotlinOutput(
            source, moduleName: "AnnotationInstanceMethods", expected: expected,
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
