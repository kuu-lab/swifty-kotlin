#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ContextParameterOverloadTests {
    private let contextFlags = [
        "explicit-context-arguments",
    ]

    private func context(_ source: String, emit: EmitMode = .kirDump) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path],
            emit: emit,
            frontendFlags: contextFlags,
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test
    func contextAndNonContextMemberOverloadsResolveWithExplicitArgument() throws {
        let ctx = context("""
        class Scope
        class Result
        @OptIn(kotlin.ExperimentalContextParameters::class)
        interface Interface {
            fun foo(): Result
            context(scope: Scope)
            fun foo(): Result
        }
        @OptIn(kotlin.ExperimentalContextParameters::class)
        fun invoke(receiver: Interface, scope: Scope): Result = receiver.foo(scope = scope)
        """, emit: .jvmJar)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.prefix(10).map { ($0.code, $0.message) })")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "foo", in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
        #expect(signature.contextParameterTypes.count == 1)
        #expect(binding.contextParameterArgumentMapping == [0: 0])
    }

    @Test
    func nullableOverloadsAreAllowedForNativeEmission() throws {
        let ctx = context("""
        class Value
        fun pick(value: Value) {}
        fun pick(value: Value?) {}
        """, emit: .executable)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.prefix(10).map { ($0.code, $0.message) })")
    }

    @Test
    func nullableOverloadsStillReportJVMErasureConflictForJVMEmission() throws {
        let ctx = context("""
        class Value
        fun pick(value: Value) {}
        fun pick(value: Value?) {}
        """, emit: .jvmJar)

        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0001"
                && $0.message == "Duplicate JVM-erased callable declaration in the same package scope."
        })
    }
}
#endif
