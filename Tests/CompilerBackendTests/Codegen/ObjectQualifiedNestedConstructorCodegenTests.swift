@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ObjectQualifiedNestedConstructorCodegenTests {
    @Test(arguments: [0, 2], [false, true])
    func executesConstructorsWithoutInitializingQualifier(optimization: Int, stdlibFromSource: Bool) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/object_qualified_nested_constructor.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "ObjectQualifiedNestedConstructor",
            expected: "7\n11\n13\n17\n19\n0\n41\n1\n23\n35\n",
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            allowDefaultStdlibLibrary: !stdlibFromSource
        )
    }

    @Test func enclosingObjectThisIsAvailableInNestedSuperConstructorCall() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/kuu_3560_nested_class_supercall_object_this.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "KUU3560NestedClassSupercallObjectThis",
            expected: "OK\n"
        )
    }
}
