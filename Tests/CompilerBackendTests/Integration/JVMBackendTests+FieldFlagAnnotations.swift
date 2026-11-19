#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jvmFieldFlagAnnotationsResolveAndMarkFields(mode: EmitMode) throws {
        let source = """
        class FieldFlags {
            @Volatile var volatileValue = 1
            @Transient var transientValue = 2
            @field:kotlin.jvm.Volatile var explicitVolatile = 3
            @field:kotlin.jvm.Transient var explicitTransient = 4
        }
        """
        let expectedFieldLines = [
            "volatile int volatileValue",
            "transient int transientValue",
            "volatile int explicitVolatile",
            "transient int explicitTransient",
        ]
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let app = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let inspection = try javap(["-p", "-classpath", app.path, "FieldFlags"])
            try #require(inspection.exitCode == 0, "\(inspection.stderr)")
            for line in expectedFieldLines {
                #expect(inspection.stdout.contains(line), "\(line) missing from:\n\(inspection.stdout)")
            }

            let reference = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let referenceInspection = try javap(["-p", "-classpath", root.appendingPathComponent("reference.jar").path, "FieldFlags"])
            try #require(referenceInspection.exitCode == 0, "\(referenceInspection.stderr)")
            for line in expectedFieldLines {
                #expect(referenceInspection.stdout.contains(line), "kotlinc reference missing \(line):\n\(referenceInspection.stdout)")
            }
        }
    }
}
#endif
