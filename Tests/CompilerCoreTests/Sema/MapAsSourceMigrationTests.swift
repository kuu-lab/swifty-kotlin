#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MapAsSourceMigrationTests {
    @Test
    func testMapAsFamilyUsesExactBundledSourceSignatures() throws {
        let source = """
        fun use(values: Map<String?, Int?>) {
            values.asIterable()
            values.asSequence()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Map.as-family calls must type-check: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let mapFQName = ["kotlin", "collections", "Map"].map(interner.intern)
            let entryFQName = ["kotlin", "collections", "Map", "Entry"].map(interner.intern)
            let mapSymbol = try #require(sema.symbols.lookup(fqName: mapFQName))
            let entrySymbol = try #require(sema.symbols.lookup(fqName: entryFQName))

            let cases: [(name: String, returnName: String, isInline: Bool)] = [
                ("asIterable", "Iterable", true),
                ("asSequence", "Sequence", false),
            ]

            for testCase in cases {
                let fqName = ["kotlin", "collections", testCase.name].map(interner.intern)
                let candidates = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard sema.symbols.isSourceBackedSymbol(symbolID),
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let receiverType = signature.receiverType,
                          case let .classType(receiverClassType) = sema.types.kind(of: receiverType)
                    else { return false }
                    return receiverClassType.classSymbol == mapSymbol
                        && signature.parameterTypes.isEmpty
                }
                let symbolID = try #require(candidates.first, "Expected bundled Map.\(testCase.name) source declaration")
                #expect(candidates.count == 1, "Expected one exact Map.\(testCase.name) source overload")

                let symbol = try #require(sema.symbols.symbol(symbolID))
                #expect(symbol.visibility == .public)
                #expect(symbol.flags.contains(.synthetic) == false)
                #expect(symbol.flags.contains(.inlineFunction) == testCase.isInline)
                #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                let sourceFileID = try #require(sema.symbols.sourceFileID(for: symbolID))
                #expect(ctx.sourceManager.path(of: sourceFileID) == "__bundled_kotlin/collections/MapHOF.kt")

                let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                #expect(signature.typeParameterSymbols.count == 2)
                guard let receiverType = signature.receiverType,
                      case let .classType(receiverClassType) = sema.types.kind(of: receiverType)
                else {
                    Issue.record("Map.\(testCase.name) must have a Map receiver")
                    continue
                }
                #expect(receiverClassType.classSymbol == mapSymbol)
                #expect(receiverClassType.args.count == 2)
                if receiverClassType.args.count == 2 {
                    guard case .out = receiverClassType.args[0] else {
                        Issue.record("Map.\(testCase.name) must preserve the out K receiver projection")
                        continue
                    }
                    guard case .invariant = receiverClassType.args[1] else {
                        Issue.record("Map.\(testCase.name) must preserve the V receiver argument")
                        continue
                    }
                }

                guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                      let returnSymbol = sema.symbols.symbol(returnClassType.classSymbol)
                else {
                    Issue.record("Map.\(testCase.name) must return a class type")
                    continue
                }
                #expect(interner.resolve(returnSymbol.name) == testCase.returnName)
                #expect(returnClassType.args.count == 1)
                guard let elementTypeArg = returnClassType.args.first else { continue }
                let elementType: TypeID
                switch elementTypeArg {
                case let .invariant(type), let .out(type):
                    elementType = type
                case .in:
                    Issue.record("Map.\(testCase.name) must return covariant entry elements")
                    continue
                case .star:
                    Issue.record("Map.\(testCase.name) must return typed entry elements")
                    continue
                }
                guard case let .classType(elementClassType) = sema.types.kind(of: elementType) else {
                    Issue.record("Map.\(testCase.name) must return Map.Entry elements")
                    continue
                }
                #expect(elementClassType.classSymbol == entrySymbol)
                #expect(elementClassType.args.count == 2)
            }
        }
    }
}
#endif
