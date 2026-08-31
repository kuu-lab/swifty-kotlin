#if canImport(Testing)
@testable import CompilerCore
import Testing

// KSP-1081: Keep the minOf source declarations aligned with Kotlin 2.3.10.
@Suite("ComparisonsMinOfSourceSurface")
struct ComparisonsMinOfSourceSurfaceTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func sourceSymbols(
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let fqName = ["kotlin", "comparisons", "minOf"].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fqName).filter { symbol in
            sema.symbols.externalLinkName(for: symbol) == nil
        }
    }

    private func hasFunction(
        _ symbols: [SymbolID],
        sema: SemaModule,
        parameters: [TypeID],
        vararg: [Bool],
        inline: Bool,
        predicate: (FunctionSignature) -> Bool = { _ in true }
    ) -> Bool {
        symbols.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol),
                  signature.parameterTypes == parameters,
                  signature.valueParameterIsVararg == vararg,
                  predicate(signature),
                  let symbolInfo = sema.symbols.symbol(symbol)
            else {
                return false
            }
            return symbolInfo.flags.contains(.inlineFunction) == inline
        }
    }

    private func isComparableGeneric(
        _ signature: FunctionSignature,
        sema: SemaModule
    ) -> Bool {
        guard signature.typeParameterSymbols.count == 1,
              let firstParameter = signature.parameterTypes.first,
              signature.parameterTypes.allSatisfy({ $0 == firstParameter }),
              case .typeParam = sema.types.kind(of: firstParameter),
              let comparableSymbol = sema.types.comparableInterfaceSymbol,
              let bound = signature.typeParameterUpperBoundsList.first?.first,
              case let .classType(boundType) = sema.types.kind(of: bound)
        else {
            return false
        }
        return boundType.classSymbol == comparableSymbol
            && boundType.args == [.invariant(firstParameter)]
    }

    @Test
    func exactMinOfOverloadsAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let symbols = sourceSymbols(sema: sema, interner: interner)
        let byte = sema.types.byteType
        let short = sema.types.shortType
        let int = sema.types.intType
        let long = sema.types.longType
        let float = sema.types.floatType
        let double = sema.types.doubleType
        let ubyte = sema.types.ubyteType
        let ushort = sema.types.ushortType
        let uint = sema.types.uintType
        let ulong = sema.types.ulongType

        for type in [byte, short] {
            #expect(hasFunction(symbols, sema: sema, parameters: [type, type], vararg: [false, false], inline: true))
            #expect(hasFunction(symbols, sema: sema, parameters: [type, type, type], vararg: [false, false, false], inline: true))
            #expect(hasFunction(symbols, sema: sema, parameters: [type, type], vararg: [false, true], inline: false))
        }

        for type in [int, long, float, double, ubyte, ushort, uint, ulong] {
            #expect(hasFunction(symbols, sema: sema, parameters: [type, type], vararg: [false, true], inline: false))
        }

        let comparableFunctions = symbols.filter { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return isComparableGeneric(signature, sema: sema)
        }
        #expect(comparableFunctions.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol),
                  let type = signature.parameterTypes.first
            else { return false }
            return signature.parameterTypes.count == 2
                && signature.valueParameterIsVararg == [false, false]
                && !sema.symbols.symbol(symbol)!.flags.contains(.inlineFunction)
                && type == signature.parameterTypes[1]
        })
        #expect(comparableFunctions.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.parameterTypes.count == 3
                && signature.valueParameterIsVararg == [false, false, false]
                && !sema.symbols.symbol(symbol)!.flags.contains(.inlineFunction)
        })
        #expect(comparableFunctions.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.parameterTypes.count == 2
                && signature.valueParameterIsVararg == [false, true]
                && !sema.symbols.symbol(symbol)!.flags.contains(.inlineFunction)
        })

        let comparatorSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Comparator"),
        ]))
        let comparatorFunctions = symbols.filter { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol),
                  signature.typeParameterSymbols.count == 1,
                  let type = signature.parameterTypes.first,
                  case .typeParam = sema.types.kind(of: type),
                  let last = signature.parameterTypes.last,
                  case let .classType(classType) = sema.types.kind(of: last)
            else {
                return false
            }
            return classType.classSymbol == comparatorSymbol
                && classType.args == [.in(type)]
        }
        #expect(comparatorFunctions.contains { symbol in
            let signature = sema.symbols.functionSignature(for: symbol)!
            return signature.parameterTypes.count == 3
                && signature.valueParameterIsVararg == [false, false, false]
                && !sema.symbols.symbol(symbol)!.flags.contains(.inlineFunction)
        })
        #expect(comparatorFunctions.contains { symbol in
            let signature = sema.symbols.functionSignature(for: symbol)!
            return signature.parameterTypes.count == 4
                && signature.valueParameterIsVararg == [false, false, false, false]
                && !sema.symbols.symbol(symbol)!.flags.contains(.inlineFunction)
        })
        #expect(comparatorFunctions.contains { symbol in
            let signature = sema.symbols.functionSignature(for: symbol)!
            return signature.parameterTypes.count == 3
                && signature.valueParameterIsVararg == [false, true, false]
                && !sema.symbols.symbol(symbol)!.flags.contains(.inlineFunction)
        })
    }
}
#endif
