@testable import CompilerCore
import Testing

@Suite
struct PreconditionSyntheticSkipTests {
    /// Regression for the bundled `kotlin/Preconditions.kt` source clashing with
    /// synthetic `require`/`check`/`error` fallback stubs. Before the KSP-002 skip
    /// guard was wired into `HeaderHelpers+SyntheticPreconditionStubs.swift`, these
    /// calls produced duplicate-definition warnings and ambiguous-overload errors.
    @Test
    func bundledPreconditionCallsTypeCheckCleanly() throws {
        let source = """
        fun test() {
            require(true)
            check(true)
            error("fail")
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = Set(ctx.diagnostics.diagnostics.map(\.code))
        #expect(
            !codes.contains("KSWIFTK-SEMA-0102"),
            "Synthetic precondition stubs duplicated bundled declarations: \(ctx.diagnostics.diagnostics)"
        )
        #expect(
            !codes.contains("KSWIFTK-SEMA-0003"),
            "Precondition calls resolved ambiguously: \(ctx.diagnostics.diagnostics)"
        )
    }

    /// `require`/`check`/`error` bundled source declarations must win over the
    /// synthetic stubs, i.e. the symbols registered for them are not synthetic.
    @Test
    func bundledPreconditionSymbolsAreNotSynthetic() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)

        let kotlinPkg = ctx.interner.intern("kotlin")
        for name in ["require", "check", "error"] {
            let functionName = ctx.interner.intern(name)
            let fqName = [kotlinPkg, functionName]
            let matchingSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      signature.receiverType == nil
                else {
                    return false
                }
                return signature.returnType == (name == "error" ? sema.types.nothingType : sema.types.unitType)
            }

            let syntheticCount = matchingSymbols.filter {
                sema.symbols.symbol($0)?.flags.contains(.synthetic) ?? false
            }.count
            #expect(
                syntheticCount == 0,
                "Expected \(name) to be served by bundled source, found \(syntheticCount) synthetic symbol(s)"
            )
        }
    }
}
