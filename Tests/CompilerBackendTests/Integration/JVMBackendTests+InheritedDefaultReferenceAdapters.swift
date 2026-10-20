#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func inheritedGenericDefaultReferenceAdaptersBoxArguments(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("inheritedGenericDefaultReferenceAdapters.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("inheritedGenericDefaultReferenceAdapters.out"), encoding: .utf8)
        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
        try repositoryStdlibRuntimeRegression(name: "inheritedGenericDefaultReferenceAdapters", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func inheritedOnlyGenericDefaultReferenceAdaptersKeepDefaultOwner(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("inheritedOnlyGenericDefaultReferenceAdapters.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("inheritedOnlyGenericDefaultReferenceAdapters.out"), encoding: .utf8)
        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
        try repositoryStdlibRuntimeRegression(name: "inheritedOnlyGenericDefaultReferenceAdapters", mode: mode)
    }
}
#endif
