#if canImport(Testing)
@testable import CompilerCore
import Testing

extension LoweringPassRegressionTests {
    @Test(arguments: [false, true])
    func testExpectActualEnumHelpersBelongToActual(reverseInputs: Bool) throws {
        let declarations = [
            "package x\nexpect enum class E { A, B }",
            "package x\nactual enum class E { A, B, C }",
        ]
        let sources = (reverseInputs ? Array(declarations.reversed()) : declarations) + [
            "import x.E\nfun main(){println(E.B.toString()); println(E.values().size)}",
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, moduleName: "ExpectActualEnum", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let enumFQName = [ctx.interner.intern("x"), ctx.interner.intern("E")]
            let actualEnum = try #require(sema.symbols.lookupAll(fqName: enumFQName).first {
                sema.symbols.symbol($0)?.flags.contains(.actualDeclaration) == true
            })
            let enumNominals = module.arena.declarations.compactMap { declaration -> SymbolID? in
                guard case let .nominalType(nominal) = declaration,
                      sema.symbols.symbol(nominal.symbol)?.fqName == enumFQName
                else { return nil }
                return nominal.symbol
            }
            #expect(enumNominals == [actualEnum])
            let entryGlobals = module.arena.declarations.compactMap { declaration -> SymbolID? in
                guard case let .global(global) = declaration,
                      let symbol = sema.symbols.symbol(global.symbol),
                      symbol.kind == .field,
                      Array(symbol.fqName.dropLast()) == enumFQName
                else { return nil }
                return global.symbol
            }
            #expect(entryGlobals.count == 3)
            for entry in entryGlobals {
                #expect(sema.symbols.parentSymbol(for: entry) == actualEnum)
            }
            let actualB = try #require(entryGlobals.first {
                sema.symbols.symbol($0)?.name == ctx.interner.intern("B")
            })
            let main = try #require(module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      function.name == ctx.interner.intern("main")
                else { return nil }
                return function
            }.first)
            let receiverRefs = main.body.compactMap { instruction -> SymbolID? in
                guard case let .constValue(_, .symbolRef(symbol)) = instruction,
                      let entry = sema.symbols.symbol(symbol),
                      Array(entry.fqName.dropLast()) == enumFQName,
                      entry.kind == .field
                else { return nil }
                return symbol
            }
            #expect(receiverRefs == [actualB])
            let enumFunctions = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      let symbol = sema.symbols.symbol(function.symbol),
                      Array(symbol.fqName.dropLast()) == enumFQName
                else { return nil }
                return function
            }
            let helpers = enumFunctions.filter { function in
                let name = ctx.interner.resolve(function.name)
                return name.contains("$enumName$") || name.hasPrefix("$enumOrdinalToName$")
            }
            #expect(helpers.count == 4)
            #expect(Set(helpers.map(\.name)).count == 4)
            for helper in helpers {
                #expect(sema.symbols.parentSymbol(for: helper.symbol) == actualEnum)
            }
            let nameHelper = try #require(helpers.first {
                ctx.interner.resolve($0.name).hasPrefix("$enumOrdinalToName$")
            })
            let entryHelpers = Set(helpers.filter { $0.symbol != nameHelper.symbol }.map(\.name))
            let referencedNames = nameHelper.body.compactMap { instruction -> InternedString? in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction,
                      entryHelpers.contains(callee)
                else { return nil }
                return callee
            }
            #expect(referencedNames.count == 3)
            #expect(Set(referencedNames) == entryHelpers)

            let valuesName = ctx.interner.intern("values")
            let valuesFunctions = enumFunctions.filter { $0.name == valuesName }
            #expect(valuesFunctions.count == 1)
            let valuesFunction = try #require(valuesFunctions.first)
            #expect(sema.symbols.parentSymbol(for: valuesFunction.symbol) == actualEnum)
            #expect(sema.bindings.callBindings.values.contains {
                $0.chosenCallee == valuesFunction.symbol
            })
        }
    }
}
#endif
