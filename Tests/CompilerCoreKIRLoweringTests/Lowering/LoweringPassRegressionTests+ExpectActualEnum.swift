#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    // KUU-2672: the paired expect enum is never lowered, so its constructor
    // has neither an internal function nor an external link name. The
    // `__kconstructor_callable` reflection thunk must be generated only for
    // the actual declaration's constructors — a thunk bound to the expect
    // side's constructor lowers its call to a bare `_<init>` external
    // reference that cannot link.
    @Test(arguments: [false, true])
    func pairedEnumConstructorReflectionOnlyReferencesActualCtors(withCompanion: Bool) throws {
        let expectDecl = withCompanion
            ? "package x\nexpect enum class E { A, B; companion object { fun n(): E } }"
            : "package x\nexpect enum class E { A, B }"
        let actualDecl = withCompanion
            ? "package x\nactual enum class E { A, B; actual companion object { actual fun n(): E = A } }\nfun main() { println(E.A === E.B) }"
            : "package x\nactual enum class E { A, B }\nfun main() { println(E.A === E.B) }"
        try withTemporaryFiles(contents: [expectDecl, actualDecl]) { paths in
            let ctx = makeCompilationContext(inputs: paths, moduleName: "ExpectActualEnum", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let module = try #require(ctx.kir)
            let enumFQName = [ctx.interner.intern("x"), ctx.interner.intern("E")]
            let ctorFQName = enumFQName + [ctx.interner.intern("<init>")]
            let enumSymbols = sema.symbols.lookupAll(fqName: enumFQName)
            let expectEnum = try #require(enumSymbols.first {
                sema.symbols.symbol($0)?.flags.contains(.expectDeclaration) == true
            })
            let actualEnum = try #require(enumSymbols.first {
                sema.symbols.symbol($0)?.flags.contains(.actualDeclaration) == true
            })
            let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
            let expectCtors = Set(ctorSymbols.filter {
                sema.symbols.parentSymbol(for: $0) == expectEnum
            })
            let actualCtors = Set(ctorSymbols.filter {
                sema.symbols.parentSymbol(for: $0) == actualEnum
            })
            #expect(expectCtors.count == 1)
            #expect(actualCtors.count == 1)

            let callableThunks = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      ctx.interner.resolve(function.name).hasPrefix("__kconstructor_callable_")
                else { return nil }
                return function
            }
            #expect(callableThunks.count == actualCtors.count)
            for thunk in callableThunks {
                for instruction in thunk.body {
                    guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "<init>"
                    else { continue }
                    #expect(symbol != nil && actualCtors.contains(symbol!))
                }
            }

            // The reflection initializer must not register a function pointer
            // for the expect-side constructor either — `symbolRef` on it has
            // no emitted target and folds to a null pointer.
            let reflectInitializers = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      ctx.interner.resolve(function.name).hasPrefix("__ctor_reflect_init_")
                else { return nil }
                return function
            }
            for initializer in reflectInitializers {
                for instruction in initializer.body {
                    guard case let .constValue(_, .symbolRef(symbol)) = instruction else { continue }
                    #expect(!expectCtors.contains(symbol))
                }
            }
        }
    }
}
#endif
