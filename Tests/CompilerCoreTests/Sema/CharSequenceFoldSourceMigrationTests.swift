@testable import CompilerCore
import Testing

/// KSP-1376: Validates that the CharSequence fold family is provided by
/// bundled Kotlin source with the inline contract and no runtime bridge.
@Suite
struct CharSequenceFoldSourceMigrationTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func foldFamilyDeclarationsAreSourceBacked() throws {
        let context = makeContextFromSource("fun noop() {}")
        try runSema(context)
        #expect(!context.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: context)))

        let sema = try #require(context.sema)
        let charSequenceSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map(context.interner.intern))
        )
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let packageFQName = ["kotlin", "text"].map(context.interner.intern)
        let expectedArities: [String: Int] = [
            "fold": 2,
            "foldIndexed": 2,
            "foldRight": 2,
            "foldRightIndexed": 2,
        ]

        for (name, arity) in expectedArities {
            let symbols = sema.symbols.lookupAll(fqName: packageFQName + [context.interner.intern(name)]).filter { id in
                guard let symbol = sema.symbols.symbol(id),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: id),
                      let signature = sema.symbols.functionSignature(for: id)
                else {
                    return false
                }
                return context.sourceManager.path(of: fileID) == sourcePath
                    && signature.receiverType == charSequenceType
                    && signature.parameterTypes.count == arity
            }

            #expect(symbols.count == 1, "Expected one CharSequence.\(name) declaration, got \(symbols.count)")
            for symbolID in symbols {
                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.flags.contains(.inlineFunction))
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            }
        }
    }

    @Test
    func foldFamilyCallsBindToBundledSource() throws {
        let context = makeContextFromSource("""
        fun direct(source: CharSequence): Int {
            source.fold(0) { accumulator, value ->
                if (value == 'b') return 11
                accumulator + value.code
            }
            source.foldIndexed(0) { index, accumulator, value ->
                if (index == 1) return 12
                accumulator + value.code
            }
            source.foldRight(0) { value, accumulator ->
                if (value == 'b') return 13
                accumulator + value.code
            }
            source.foldRightIndexed(0) { index, value, accumulator ->
                if (index == 1) return 14
                accumulator + value.code
            }
            return -1
        }
        fun safe(source: CharSequence?): Int {
            source?.fold(0) { accumulator, value ->
                if (value == 'b') return 21
                accumulator + value.code
            }
            source?.foldIndexed(0) { index, accumulator, value ->
                if (index == 1) return 22
                accumulator + value.code
            }
            source?.foldRight(0) { value, accumulator ->
                if (value == 'b') return 23
                accumulator + value.code
            }
            source?.foldRightIndexed(0) { index, value, accumulator ->
                if (index == 1) return 24
                accumulator + value.code
            }
            return -1
        }
        fun named(source: CharSequence, seed: Int): Int {
            source.fold(initial = seed, operation = { accumulator, value ->
                if (value == 'b') return accumulator
                accumulator + value.code
            })
            source.foldIndexed(initial = seed, operation = { index, accumulator, value ->
                if (index == 1) return accumulator
                accumulator + value.code
            })
            source.foldRight(initial = seed, operation = { value, accumulator ->
                if (value == 'b') return accumulator
                accumulator + value.code
            })
            source.foldRightIndexed(initial = seed, operation = { index, value, accumulator ->
                if (index == 1) return accumulator
                accumulator + value.code
            })
            return -1
        }
        """)
        try runSema(context)
        #expect(!context.diagnostics.hasError, Comment(rawValue: diagnosticSummary(in: context)))

        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let userFileID = try #require(context.sourceManager.fileIDs().first {
            context.sourceManager.origin(of: $0) == .user
        })
        let names = Set(["fold", "foldIndexed", "foldRight", "foldRightIndexed"])
        var calls = 0

        for index in ast.arena.exprs.indices {
            let expressionID = ExprID(rawValue: Int32(index))
            guard let expression = ast.arena.expr(expressionID),
                  ast.arena.exprRange(expressionID)?.start.file == userFileID
            else {
                continue
            }

            let calleeName: InternedString
            switch expression {
            case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _):
                calleeName = name
            default:
                continue
            }

            guard names.contains(context.interner.resolve(calleeName)),
                  let binding = sema.bindings.callBinding(for: expressionID)
            else {
                continue
            }

            calls += 1
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            let fileID = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
            #expect(context.sourceManager.path(of: fileID) == sourcePath)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
        }

        #expect(calls == 12, "Expected twelve direct, safe, and named CharSequence fold-family calls, got \(calls)")
    }
}

private func diagnosticSummary(in context: CompilationContext) -> String {
    context.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
}
