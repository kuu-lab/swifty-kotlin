@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ExtensionPropertySetterAssignmentTests {
    private let declarations = """
    var <T> T.receiverCallback: T.(String) -> String
        get() = { value: String -> value }
        set(value: T.(String) -> String) {}

    var Int.plainCallback: (String) -> String
        get() = { it }
        set(value) {}

    var Number.selectedCallback: (Boolean) -> Boolean
        get() = { it }
        set(value) {}
    var Int.selectedCallback: (String) -> String
        get() = { it }
        set(value) {}
    """

    private func context(_ source: String, inputs: [String] = ["/virtual/extension-property-setter.kt"]) -> CompilationContext {
        let ctx = makeCompilationContext(inputs: inputs, includeStdlib: false)
        for (path, text) in zip(inputs, source.components(separatedBy: "\n--- FILE ---\n")) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(text.utf8))
        }
        return ctx
    }

    @Test
    func receiverFunctionLambdasAndOverloadsAreContextualized() throws {
        let ctx = context(declarations + """

        fun valid() {
            1.receiverCallback = { "OK" }
            1.receiverCallback = { value: String -> value }
            1.plainCallback = { it }

            val typed: Int.(String) -> String = { value: String -> value }
            1.receiverCallback = typed

            var local: Int.(String) -> String = { value: String -> value }
            local = { value: String -> value }

            1.selectedCallback = { value: String -> value }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func setterValueTypeAndOverloadBoundaryRejectMismatchedLambdas() throws {
        let ctx = context(declarations + """

        fun invalid() {
            1.receiverCallback = { value: Int -> value.toString() }
            1.plainCallback = { 1 }
            1.selectedCallback = { value: Boolean -> value }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Mismatched setter lambdas must be rejected")
    }

    @Test
    func privateExtensionSetterRemainsInaccessibleFromAnotherFile() throws {
        let paths = ["/virtual/private-extension-setter.kt", "/virtual/extension-setter-consumer.kt"]
        let ctx = context("""
        var Int.privateCallback: (String) -> String
            get() = { it }
            private set(value) {}
        --- FILE ---
        fun invalid() { 1.privateCallback = { value: String -> value } }
        """, inputs: paths)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" },
            "A private extension setter must remain inaccessible across files: \(ctx.diagnostics.diagnostics)"
        )
    }
}
