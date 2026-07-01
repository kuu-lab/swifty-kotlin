#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
@MainActor
struct NativeCInteropUseContentsLoweringTests {
    /// Regression: `CValue<T>.useContents { ... }` lowers as an implicit-receiver
    /// scope function, so the contained C variable must be copied into the
    /// lambda's synthetic receiver storage before the block runs. Without the
    /// initializing `.copy`, every `this` reference inside the block reads an
    /// uninitialized expression (see scopeUseContents in
    /// CallLowerer+ScopeFunctionLowering).
    @Test
    func testUseContentsLowersReceiverInitializationCopy() throws {
        let source = """
        import kotlinx.cinterop.CStructVar
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.useContents

        @ExperimentalForeignApi
        fun <T : CStructVar> expose(value: CValue<T>): T {
            return value.useContents { this }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "UseContentsLowering", emit: .kirDump)
            try runToKIR(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let expose = try findKIRFunction(named: "expose", in: module, interner: ctx.interner)

            func symbol(of exprID: KIRExprID) -> SymbolID? {
                guard case let .symbolRef(symbol) = module.arena.expr(exprID) else { return nil }
                return symbol
            }

            // The receiver initialization is a `.copy` from one symbol reference
            // (the lowered `value` receiver) into another (the synthetic
            // implicit-receiver storage captured by the block).
            let receiverCopies = expose.body.compactMap { instruction -> (from: SymbolID, to: KIRExprID, toSymbol: SymbolID)? in
                guard case let .copy(from, to) = instruction,
                      let fromSymbol = symbol(of: from),
                      let toSymbol = symbol(of: to)
                else { return nil }
                return (from: fromSymbol, to: to, toSymbol: toSymbol)
            }

            let receiverCopy = try #require(
                receiverCopies.first,
                "useContents lowering must copy the CValue receiver into the block's synthetic receiver storage; body: \(expose.body)"
            )
            #expect(
                receiverCopy.from != receiverCopy.toSymbol,
                "Receiver copy should move the lowered receiver into a distinct synthetic storage symbol"
            )

            // The initialized storage must actually be consumed (captured by the
            // block) after being written — otherwise the copy would be dead.
            let copyIndex = try #require(expose.body.firstIndex { instruction in
                if case let .copy(_, to) = instruction { return to == receiverCopy.to }
                return false
            })
            let storageIsRead = expose.body[(copyIndex + 1)...].contains { instruction in
                guard case let .call(_, _, arguments, _, _, _, _, _) = instruction else { return false }
                return arguments.contains(receiverCopy.to)
            }
            #expect(storageIsRead, "Initialized useContents receiver storage must be captured by the block")
        }
    }
}
#endif
