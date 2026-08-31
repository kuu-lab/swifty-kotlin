#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-987: Iterable.partition is a bundled Kotlin source declaration rather
/// than a compiler/runtime bridge, and its public source shape is inline.
@Suite
struct IterablePartitionSourceMigrationTests {
    @Test
    func iterablePartitionIsSourceBackedInlineAndUnlinked() throws {
        let source = """
        fun probe(values: Iterable<Int>): Pair<List<Int>, List<Int>> {
            return values.partition { it % 2 == 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Iterable.partition to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "partition"
            }, "Expected Iterable.partition member call")
            let binding = try #require(sema.bindings.callBinding(for: call))
            let chosen = try #require(binding.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosen))
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            let receiver = try #require(signature.receiverType)
            let iterableSymbol = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Iterable"),
            ]))

            #expect(sema.symbols.isSourceBackedSymbol(chosen))
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(signature.parameterTypes.count == 1)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                Issue.record("Iterable.partition receiver was not a class type")
                return
            }
            #expect(receiverClass.classSymbol == iterableSymbol)
            #expect(
                sema.bindings.exprType(for: call) != nil,
                "Expected Pair<List<Int>, List<Int>> result type"
            )
        }
    }
}
#endif
