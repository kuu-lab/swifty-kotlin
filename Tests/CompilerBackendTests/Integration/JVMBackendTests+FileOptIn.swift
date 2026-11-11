#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func fileOptInEnablesExperimentalCalls(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            @file:OptIn(ExampleExperimental::class)
            @RequiresOptIn annotation class ExampleExperimental
            @ExampleExperimental fun checked(): Int = 42
            fun main() { println(checked()) }
            """, expected: "42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func fileOptInIsLimitedToItsFileAndMarkers(mode: EmitMode) throws {
        try withWorkspace { root in
            let (exitCode, diagnostics) = try compile("""
            @file:OptIn(ExampleExperimental::class)
            @RequiresOptIn annotation class ExampleExperimental
            @RequiresOptIn annotation class OtherExperimental
            @ExampleExperimental fun checked(): Int = 42
            @OtherExperimental fun other(): Int = 7
            fun acceptedInThisFile(): Int = checked()
            fun requiresAnotherMarker(): Int = other()
            """, root: root, mode: mode, additionalSources: [
                ("Unopted.kt", """
                fun requiresOptIn(): Int = checked()
                fun acceptedOutside(): Int = acceptedInThisFile()
                """)
            ])

            #expect(exitCode != 0)
            assertExpectedDiagnostics([
                .error("KSWIFTK-SEMA-OPT-IN", containing: "'ExampleExperimental'"),
                .error("KSWIFTK-SEMA-OPT-IN", containing: "'OtherExperimental'"),
            ], in: diagnostics)

            let files = Set(diagnostics.filter {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-OPT-IN"
            }.compactMap { $0.primaryRange?.start.file })
            #expect(files.count == 2)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func declarationOptInStillEnablesExperimentalCalls(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            @RequiresOptIn(message = "Experimental example", level = RequiresOptIn.Level.ERROR)
            annotation class ExampleExperimental
            @ExampleExperimental fun checked(): Int = 42

            @OptIn(ExampleExperimental::class)
            fun fromFunction(): Int = checked()

            @OptIn(ExampleExperimental::class)
            class Caller {
                fun fromClass(): Int = checked()
            }

            fun main() {
                println(fromFunction())
                println(Caller().fromClass())
            }
            """, expected: "42\n42\n", mode: mode, root: root)

            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let marker = try javap(["-v", "-classpath", output.path, "ExampleExperimental"])
            try #require(marker.exitCode == 0, "\(marker.stderr)")
            let binaryAnnotations = try #require(marker.stdout.range(of: "RuntimeInvisibleAnnotations:"))
            #expect(marker.stdout[binaryAnnotations.upperBound...].contains("kotlin.RequiresOptIn("))
            #expect(marker.stdout[binaryAnnotations.upperBound...].contains(#"message="Experimental example""#))
        }
    }

    @Test
    func optInRejectsBackingFieldTarget() throws {
        try withWorkspace { root in
            let (exitCode, diagnostics) = try compile("""
            @RequiresOptIn annotation class ExampleExperimental
            @field:OptIn(ExampleExperimental::class)
            val invalid = 42
            """, root: root, mode: .jvmClass)

            #expect(exitCode != 0)
            assertExpectedDiagnostics([
                .error("KSWIFTK-SEMA-ANNOTATION-TARGET", containing: "Annotation 'OptIn' is not applicable to a backing field.")
            ], in: diagnostics)
        }
    }
}
#endif
