@testable import CompilerCore
import Foundation
import Testing

/// KUU-1389: `Set`/`Collection`-family receivers inherit `filterTo`,
/// `filterNotTo`, and `filterIndexedTo` from `Iterable<T>` upstream, but the
/// destination-HOF arm only attempted the bundled Iterable declaration for a
/// nominal `Iterable` static type. The calls bound a result type with no
/// callee and lowered to phantom `_filterTo`-style symbols (deterministic
/// LINK-0001) — including `Map.entries`/`keys`/`values`, the documented
/// workaround for the missing `Map.filterTo(MutableCollection)` overload that
/// does not exist upstream. Pin that each call binds the bundled
/// `kotlin.collections` `Iterable` declaration.
@Suite
struct SetDestinationHOFBindingTests {
    @Test(arguments: [
        ("s.filterTo(mutableListOf()) { it > 1 }", "filterTo"),
        ("s.filterNotTo(mutableListOf()) { it > 1 }", "filterNotTo"),
        ("s.filterIndexedTo(mutableListOf()) { index, _ -> index > 0 }", "filterIndexedTo"),
        ("ms.filterTo(mutableListOf()) { it > 1 }", "filterTo"),
        ("ms.filterNotTo(mutableListOf()) { it > 1 }", "filterNotTo"),
        ("ms.filterIndexedTo(mutableListOf()) { index, _ -> index > 0 }", "filterIndexedTo"),
        ("c.filterTo(mutableListOf()) { it > 1 }", "filterTo"),
        ("c.filterNotTo(mutableListOf()) { it > 1 }", "filterNotTo"),
        ("c.filterIndexedTo(mutableListOf()) { index, _ -> index > 0 }", "filterIndexedTo"),
        ("m.entries.filterTo(mutableListOf()) { it.key > 1 }", "filterTo"),
        ("m.entries.filterNotTo(mutableListOf()) { it.key > 1 }", "filterNotTo"),
        ("m.entries.filterIndexedTo(mutableListOf()) { index, _ -> index > 0 }", "filterIndexedTo"),
        ("m.keys.filterTo(mutableListOf()) { it > 1 }", "filterTo"),
        ("m.values.filterTo(mutableListOf()) { it == \"b\" }", "filterTo"),
    ])
    func setFamilyDestinationHOFBindsBundledIterableDecl(
        call: String,
        calleeName: String
    ) throws {
        let source = """
        fun probe(s: Set<Int>, ms: MutableSet<Int>, c: Collection<Int>, m: Map<Int, String>) {
            \(call)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected \(call) to type-check, got \(errors)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callID = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(callee) == calleeName
            })
            let chosenCallee = try #require(
                sema.bindings.callBindings[callID]?.chosenCallee,
                "\(call) must bind a concrete callee, not a phantom symbol"
            )
            let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
            let receiverType = try #require(signature.receiverType)
            let (_, receiverSymbol) = try #require(resolveClassTypeSymbol(receiverType, sema: sema))
            #expect(receiverSymbol.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("Iterable"),
            ], "Expected \(call) to bind the bundled Iterable.\(calleeName) declaration")
        }
    }

    /// The issue's sample form. kotlin-stdlib has no
    /// `Map.filterTo(MutableCollection)` overload — the only `Map` destination
    /// overload takes `MutableMap` — so kotlinc rejects this and KSwiftK must
    /// keep rejecting it rather than diverging from upstream.
    @Test
    func mapReceiverCollectionDestinationStaysRejected() throws {
        let source = """
        fun probe(m: Map<Int, String>) {
            m.filterTo(mutableListOf()) { it.key > 1 }
            m.filterNotTo(mutableListOf()) { it.key > 1 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 2, "Expected both Map.filter*To list-destination calls to be rejected, got \(errors)")
            for error in errors {
                #expect(error.code == "KSWIFTK-TYPE-0001", "Expected destination type-mismatch, got \(error)")
            }
        }
    }
}
