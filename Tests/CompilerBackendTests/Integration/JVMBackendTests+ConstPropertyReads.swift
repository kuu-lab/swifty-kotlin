#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: ["companionPropertyCallableReferences", "constCompanionValues", "interfaceCompanionConstants", "constPropertyCallerArityContracts", "constPropertyInitialization", "objectConstNoLazyInitialization", "constPropertyReflectionFields"], [EmitMode.jvmClass, .jvmJar])
    func constPropertiesUseFieldsWithoutCompanionGetters(name: String, mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent(name + ".kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent(name + ".out"), encoding: .utf8)
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
            let candidate = root.appendingPathComponent(mode == .jvmJar ? "own.jar" : "own-classes")
            let cross = try java(["-cp", candidate.path + ":" + m11Runtime(), "HelloKt"])
            #expect(cross.stdout == expected)
            #expect(cross.stderr.isEmpty)
        }
    }

    @Test
    func constFieldOwnersAndAccessorAbsenceMatchKotlin() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("constPropertyCallerArityContracts.kt"), encoding: .utf8)
        try withWorkspace { root in
            let library = try ownStdlibLibrary()
            let app = try m22Build(root: root, sources: [("hello.kt", source)], name: "fields.jar", mode: .jvmJar, classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let expectedFields = [
                "ConstInterface": true, "ConstInterface$Named": true,
                "ConstObject": true, "ConstClass": true, "ConstClass$Named": false,
            ]
            for (owner, present) in expectedFields {
                let output = try jvmTool("javap", ["-p", "-cp", app.0.path, owner], root: root).stdout
                #expect(output.contains("public static final int X;") == present, "\(owner): \(output)")
                #expect(!output.contains("getX("), "Const properties have no getter: \(owner)")
            }
            let facade = try jvmTool("javap", ["-p", "-cp", app.0.path, "HelloKt"], root: root).stdout
            #expect(facade.contains("public static final int TOP;"))
            #expect(!facade.contains("getTOP("))
            for (owner, present) in ["PrivateInterface": false, "PrivateInterface$Named": true, "PrivateClass": true, "PrivateClass$Companion": false] {
                let output = try jvmTool("javap", ["-p", "-cp", app.0.path, owner], root: root).stdout
                #expect(output.contains("private static final java.lang.String SECRET;") == present, "\(owner): \(output)")
            }
        }
    }
}
#endif
