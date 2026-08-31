@testable import CompilerCore
import Testing

/// KSP-1363: Validates the three source-backed `Appendable.appendLine` overloads.
@Suite
struct AppendableAppendLineFunctionTests {
    @Test func testAppendLineOverloadsResolveInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.text.Appendable
        import kotlin.text.StringBuilder

        fun appendLines(target: Appendable): Appendable {
            target.appendLine()
            target.appendLine(null)
            return target.appendLine('!')
        }

        fun appendToBuilder(): String {
            val builder = StringBuilder()
            appendLines(builder)
            return builder.toString()
        }
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Appendable.appendLine overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let appendableSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "text", "Appendable"].map { interner.intern($0) })
        )
        let appendableType = sema.types.make(.classType(ClassType(
            classSymbol: appendableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map { interner.intern($0) })
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableCharSequenceType = sema.types.makeNullable(charSequenceType)
        let expectedParameters: [[TypeID]] = [
            [],
            [nullableCharSequenceType],
            [sema.types.charType],
        ]

        let appendLineSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("appendLine"),
        ])
        #expect(appendLineSymbols.count == 3)

        for parameters in expectedParameters {
            let symbolID = try #require(
                appendLineSymbols.first { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                    return signature.receiverType == appendableType
                        && signature.parameterTypes == parameters
                },
                "Expected Appendable.appendLine overload with parameters \(parameters)"
            )
            let symbol = try #require(sema.symbols.symbol(symbolID))
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(signature.returnType == appendableType)
            #expect(symbol.declSite != nil)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
        }
    }
}
