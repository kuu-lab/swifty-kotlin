@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// BUG-141 regression coverage: reading an interface's stored/abstract property
// through an interface-typed receiver (object expression, named class, function
// parameter, or a custom getter) must dispatch to the implementing getter via
// the interface itable. Before the fix, the caller emitted a direct call to an
// undefined `<propertyName>` symbol and the program failed to link
// (`KSWIFTK-LINK-0001`); the object-side getters were never registered in the
// itable either.
private func runInterfacePropertyDispatchCodegenPipeline(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
        target: defaultTargetTriple()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

final class CodegenBackendInterfacePropertyDispatchTests: XCTestCase {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runInterfacePropertyDispatchCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, expected, file: file, line: line)
        }
    }

    func testObjectExpressionStoredPropertyReadThroughInterface() throws {
        // The canonical minimal repro from TODO.md BUG-141.
        let source = """
        interface Holder { val value: Int }
        fun make(): Holder = object : Holder { override val value: Int = 42 }
        fun main() { println(make().value) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141ObjectStoredProperty",
            expected: "42\n"
        )
    }

    func testNamedClassStoredPropertyReadThroughInterface() throws {
        let source = """
        interface Holder { val value: Int }
        class Impl : Holder { override val value: Int = 42 }
        fun make(): Holder = Impl()
        fun main() { println(make().value) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141NamedClassStoredProperty",
            expected: "42\n"
        )
    }

    func testInterfaceTypedParameterPropertyRead() throws {
        let source = """
        interface Holder { val value: Int }
        class Impl : Holder { override val value: Int = 42 }
        fun useHolder(h: Holder): Int = h.value
        fun main() { println(useHolder(Impl())) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141InterfaceParameter",
            expected: "42\n"
        )
    }

    func testCustomGetterPropertyReadThroughInterface() throws {
        let source = """
        interface Holder { val value: Int }
        fun make(): Holder = object : Holder { override val value: Int get() = 42 }
        fun main() { println(make().value) }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug141CustomGetter",
            expected: "42\n"
        )
    }

    // BUG-183: an implicit-receiver read inside an interface default method body
    // (`value` meaning `this.value`) must dispatch through the itable as well;
    // previously it called the interface's own abstract getter, whose placeholder
    // body returns null, so the default method observed 0.
    func testImplicitReceiverPropertyReadInsideInterfaceDefaultMethod() throws {
        let source = """
        interface Holder {
            val value: Int
            fun doubled(): Int = value * 2
            fun sum(other: Holder): Int = value + other.value
        }
        class Impl : Holder { override val value: Int = 21 }
        fun main() {
            val holder: Holder = Impl()
            println(holder.doubled())
            println(holder.sum(Impl()))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "Bug183ImplicitReceiverInterfaceProperty",
            expected: "42\n42\n"
        )
    }

    func testCanonicalDiffCaseInterfaceStoredPropertyDispatch() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerBackendTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/interface_stored_property_dispatch.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "Bug141InterfaceStoredPropertyDispatch",
            expected:
                """
                1
                2
                42
                7
                42
                kotlin
                """ + "\n"
        )
    }
}
