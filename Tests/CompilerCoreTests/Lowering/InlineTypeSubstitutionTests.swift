#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

struct InlineTypeSubstitutionTests {
    @Test
    func substitutesNestedNullableGenericAndFunctionReceiverTypesForImportedInline() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let bindings = BindingTable()
        let diagnostics = DiagnosticEngine()

        let package = interner.intern("inlineSubstitution")
        let inlineName = interner.intern("importedInline")
        let inlineSymbol = symbols.define(
            kind: .function,
            name: inlineName,
            fqName: [package, inlineName],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction, .importedLibrary]
        )
        let typeParameterSymbols = ["T", "U", "V"].map { name in
            let internedName = interner.intern(name)
            return symbols.define(
                kind: .typeParameter,
                name: internedName,
                fqName: [package, inlineName, internedName],
                declSite: nil,
                visibility: .private
            )
        }
        let tType = types.make(.typeParam(TypeParamType(symbol: typeParameterSymbols[0])))
        let nullableTType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbols[0],
            nullability: .nullable
        )))
        let nullableUType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbols[1],
            nullability: .nullable
        )))
        let vType = types.make(.typeParam(TypeParamType(symbol: typeParameterSymbols[2])))

        let boxSymbol = symbols.define(
            kind: .class,
            name: interner.intern("Box"),
            fqName: [package, interner.intern("Box")],
            declSite: nil,
            visibility: .public
        )
        let expectedBoxType = types.make(.classType(ClassType(
            classSymbol: boxSymbol,
            args: [.invariant(nullableTType)],
            nullability: .nullable
        )))
        let actualBoxType = types.make(.classType(ClassType(
            classSymbol: boxSymbol,
            args: [.invariant(types.stringType)],
            nullability: .nullable
        )))

        let expectedFunctionType = types.make(.functionType(FunctionType(
            receiver: nullableUType,
            params: [vType],
            returnType: nullableUType,
            nullability: .nullable
        )))
        let actualFunctionType = types.make(.functionType(FunctionType(
            receiver: types.intType,
            params: [types.stringType],
            returnType: types.intType,
            nullability: .nullable
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [expectedBoxType, expectedFunctionType],
                returnType: expectedFunctionType,
                typeParameterSymbols: typeParameterSymbols
            ),
            for: inlineSymbol
        )

        let boxArgument = arena.appendTemporary(type: actualBoxType)
        let functionArgument = arena.appendTemporary(type: actualFunctionType)
        let inlineTarget = KIRFunction(
            symbol: inlineSymbol,
            name: inlineName,
            params: [
                KIRParameter(symbol: SymbolID(rawValue: 100), type: expectedBoxType),
                KIRParameter(symbol: SymbolID(rawValue: 101), type: expectedFunctionType),
            ],
            returnType: expectedFunctionType,
            body: [],
            isSuspend: false,
            isInline: true
        )
        let module = KIRModule(files: [], arena: arena)
        let sema = makeSemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        ).ctx
        let ctx = makeKIRContext(
            moduleName: "InlineTypeSubstitution",
            interner: interner,
            sema: sema,
            diagnostics: diagnostics
        )

        let substitution = try #require(
            InlineTypeSubstitution.build(
                inlineTarget: inlineTarget,
                arguments: [boxArgument, functionArgument],
                module: module,
                ctx: ctx
            )
        )

        let expectedConcreteBox = types.make(.classType(ClassType(
            classSymbol: boxSymbol,
            args: [.invariant(types.makeNullable(types.stringType))],
            nullability: .nullable
        )))
        #expect(substitution.applying(to: expectedBoxType, in: ctx) == expectedConcreteBox)
        #expect(substitution.applying(to: tType, in: ctx) == types.stringType)

        let expectedConcreteFunction = types.make(.functionType(FunctionType(
            receiver: types.makeNullable(types.intType),
            params: [types.stringType],
            returnType: types.makeNullable(types.intType),
            nullability: .nullable
        )))
        #expect(substitution.applying(to: expectedFunctionType, in: ctx) == expectedConcreteFunction)
        #expect(substitution.soleSubstitutedType == nil)
        #expect(substitution.substitution.count == 3)
    }

    @Test
    func buildsReifiedTokenValuesFromImportedSignatureIndices() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        let package = interner.intern("inlineTokens")
        let inlineName = interner.intern("tokenized")
        let inlineSymbol = symbols.define(
            kind: .function,
            name: inlineName,
            fqName: [package, inlineName],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction, .importedLibrary]
        )
        let typeParameterSymbols = ["T", "U"].map { name in
            let internedName = interner.intern(name)
            return symbols.define(
                kind: .typeParameter,
                name: internedName,
                fqName: [package, inlineName, internedName],
                declSite: nil,
                visibility: .private
            )
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: types.unitType,
                typeParameterSymbols: typeParameterSymbols,
                reifiedTypeParameterIndices: [0, 1, 99]
            ),
            for: inlineSymbol
        )
        let sema = makeSemaModule(
            symbols: symbols,
            types: types,
            diagnostics: diagnostics
        ).ctx
        let ctx = makeKIRContext(
            moduleName: "InlineReifiedTokens",
            interner: interner,
            sema: sema,
            diagnostics: diagnostics
        )
        let hiddenT = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameterSymbols[0])
        let hiddenU = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: typeParameterSymbols[1])
        let tokenT = KIRExprID(rawValue: 10)
        let tokenU = KIRExprID(rawValue: 11)
        let target = KIRFunction(
            symbol: inlineSymbol,
            name: inlineName,
            params: [
                KIRParameter(symbol: hiddenU, type: types.anyType),
                KIRParameter(symbol: hiddenT, type: types.anyType),
            ],
            returnType: types.unitType,
            body: [],
            isSuspend: false,
            isInline: true
        )

        let values = InlineReifiedTypeTokens.buildTypeParamTokenValues(
            inlineTarget: target,
            parameterValues: [hiddenT: tokenT, hiddenU: tokenU],
            ctx: ctx
        )

        #expect(values[typeParameterSymbols[0]] == tokenT)
        #expect(values[typeParameterSymbols[1]] == tokenU)
        #expect(values.count == 2)
    }
}
#endif
