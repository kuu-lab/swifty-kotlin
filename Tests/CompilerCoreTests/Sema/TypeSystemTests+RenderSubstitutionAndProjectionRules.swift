@testable import CompilerCore
import Testing

extension TypeSystemTests {
    @Test
    func testRenderTypeForBuiltIns() {
        let ts = TypeSystem()
        #expect(ts.renderType(ts.errorType) == "<error>")
        #expect(ts.renderType(ts.unitType) == "Unit")
        #expect(ts.renderType(ts.nothingType) == "Nothing")
        #expect(ts.renderType(ts.anyType) == "Any")
        #expect(ts.renderType(ts.nullableAnyType) == "Any?")
    }

    @Test
    func testRenderTypeForPrimitives() {
        let ts = TypeSystem()
        #expect(ts.renderType(ts.make(.primitive(.boolean, .nonNull))) == "Boolean")
        #expect(ts.renderType(ts.make(.primitive(.char, .nonNull))) == "Char")
        #expect(ts.renderType(ts.make(.primitive(.int, .nonNull))) == "Int")
        #expect(ts.renderType(ts.make(.primitive(.long, .nonNull))) == "Long")
        #expect(ts.renderType(ts.make(.primitive(.float, .nonNull))) == "Float")
        #expect(ts.renderType(ts.make(.primitive(.double, .nonNull))) == "Double")
        #expect(ts.renderType(ts.make(.primitive(.string, .nonNull))) == "String")
    }

    @Test
    func testRenderTypeNullablePrimitive() {
        let ts = TypeSystem()
        #expect(ts.renderType(ts.make(.primitive(.int, .nullable))) == "Int?")
    }

    @Test
    func testRenderTypePlatformNullabilitySuffix() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        let platformAny = ts.withNullability(.platformType, for: ts.anyType)
        #expect(ts.renderType(platformInt) == "Int!")
        #expect(ts.renderType(platformAny) == "Any!")
    }

    @Test
    func testRenderTypeClassType() {
        let ts = TypeSystem()
        let ct = ts.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 5))))
        #expect(ts.renderType(ct).contains("Class#5"))
    }

    @Test
    func testRenderTypeClassTypeNullable() {
        let ts = TypeSystem()
        let ct = ts.make(.classType(ClassType(classSymbol: SymbolID(rawValue: 3), nullability: .nullable)))
        #expect(ts.renderType(ct).hasSuffix("?"))
    }

    @Test
    func testRenderTypeTypeParam() {
        let ts = TypeSystem()
        let tp = ts.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 7))))
        #expect(ts.renderType(tp) == "T#7")
    }

    @Test
    func testRenderTypeTypeParamNullable() {
        let ts = TypeSystem()
        let tp = ts.make(.typeParam(TypeParamType(symbol: SymbolID(rawValue: 2), nullability: .nullable)))
        #expect(ts.renderType(tp) == "T#2?")
    }

    @Test
    func testRenderTypeFunctionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ft = ts.make(.functionType(FunctionType(params: [intType], returnType: intType)))
        let rendered = ts.renderType(ft)
        #expect(rendered.contains("(Int) -> Int"))
    }

    @Test
    func testRenderTypeSuspendFunctionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ft = ts.make(.functionType(FunctionType(params: [], returnType: intType, isSuspend: true)))
        let rendered = ts.renderType(ft)
        #expect(rendered.hasPrefix("suspend "))
    }

    @Test
    func testRenderTypeFunctionTypeWithReceiver() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        let ft = ts.make(.functionType(FunctionType(receiver: stringType, params: [], returnType: intType)))
        let rendered = ts.renderType(ft)
        #expect(rendered.contains("String."))
    }

    @Test
    func testRenderTypeFunctionTypeWithContextReceivers() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        let ft = ts.make(.functionType(FunctionType(
            contextReceivers: [stringType, intType],
            receiver: stringType,
            params: [intType],
            returnType: intType
        )))
        #expect(ts.renderType(ft) == "context(String, Int) String.(Int) -> Int")
    }

    @Test
    func testRenderTypeIntersection() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.make(.primitive(.string, .nonNull))
        let inter = ts.make(.intersection([intType, stringType]))
        let rendered = ts.renderType(inter)
        #expect(rendered.contains(" & "))
    }

    @Test
    func testRenderTypeClassTypeWithTypeArgs() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ct = ts.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 0),
            args: [.invariant(intType), .out(intType), .in(intType), .star]
        )))
        let rendered = ts.renderType(ct)
        #expect(rendered.contains("out "))
        #expect(rendered.contains("in "))
        #expect(rendered.contains("*"))
    }

    // MARK: - substituteTypeParameters

    @Test
    func testSubstituteTypeParameterReplacesMatching() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try #require(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: tp,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )
        #expect(result == intType)
    }

    @Test
    func testSubstituteTypeParameterLeavesUnmatchedAlone() {
        let ts = TypeSystem()
        let tpSym = SymbolID(rawValue: 0)
        let otherSym = SymbolID(rawValue: 1)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let varMap = ts.makeTypeVarBySymbol([otherSym])
        let result = ts.substituteTypeParameters(
            in: tp,
            substitution: [:],
            typeVarBySymbol: varMap
        )
        #expect(result == tp)
    }

    @Test
    func testSubstituteInClassTypeArgs() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let classSym = SymbolID(rawValue: 10)
        let classWithT = ts.make(.classType(ClassType(
            classSymbol: classSym,
            args: [.invariant(tp)]
        )))

        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try #require(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: classWithT,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case let .classType(ct) = ts.kind(of: result) {
            #expect(ct.args.count == 1)
            if case let .invariant(inner) = ct.args[0] {
                #expect(inner == intType)
            } else {
                Issue.record("Expected invariant type arg")
            }
        } else {
            Issue.record("Expected classType after substitution")
        }
    }

    @Test
    func testSubstituteInFunctionType() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let ft = ts.make(.functionType(FunctionType(params: [tp], returnType: tp)))
        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try #require(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: ft,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case let .functionType(resultFt) = ts.kind(of: result) {
            #expect(resultFt.params == [intType])
            #expect(resultFt.returnType == intType)
        } else {
            Issue.record("Expected functionType after substitution")
        }
    }

    @Test
    func testSubstituteInFunctionTypeContextReceivers() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let ft = ts.make(.functionType(FunctionType(
            contextReceivers: [tp],
            receiver: tp,
            params: [tp],
            returnType: tp
        )))
        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try #require(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: ft,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case let .functionType(resultFt) = ts.kind(of: result) {
            #expect(resultFt.contextReceivers == [intType])
            #expect(resultFt.receiver == intType)
            #expect(resultFt.params == [intType])
            #expect(resultFt.returnType == intType)
        } else {
            Issue.record("Expected functionType after substitution")
        }
    }

    @Test
    func testSubstituteNullableTypeParameterPreservesNullableWrapper() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nullableIntType = ts.make(.primitive(.int, .nullable))
        let tpSym = SymbolID(rawValue: 0)
        let nullableTypeParam = ts.make(.typeParam(TypeParamType(symbol: tpSym, nullability: .nullable)))

        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try #require(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: nullableTypeParam,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        #expect(result == nullableIntType)
    }

    @Test
    func testSubstituteInIntersectionType() throws {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let tpSym = SymbolID(rawValue: 0)
        let tp = ts.make(.typeParam(TypeParamType(symbol: tpSym)))

        let inter = ts.make(.intersection([tp, ts.anyType]))
        let varMap = ts.makeTypeVarBySymbol([tpSym])
        let tv = try #require(varMap[tpSym])
        let result = ts.substituteTypeParameters(
            in: inter,
            substitution: [tv: intType],
            typeVarBySymbol: varMap
        )

        if case let .intersection(parts) = ts.kind(of: result) {
            #expect(parts.contains(intType))
        } else {
            Issue.record("Expected intersection after substitution")
        }
    }

    @Test
    func testSubstituteNoOpForPrimitive() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.substituteTypeParameters(in: intType, substitution: [:], typeVarBySymbol: [:])
        #expect(result == intType)
    }

    @Test
    func testSubstituteClassTypeNoChangeReturnsSameID() {
        let ts = TypeSystem()
        let classSym = SymbolID(rawValue: 0)
        let intType = ts.make(.primitive(.int, .nonNull))
        let ct = ts.make(.classType(ClassType(classSymbol: classSym, args: [.invariant(intType)])))
        let result = ts.substituteTypeParameters(in: ct, substitution: [:], typeVarBySymbol: [:])
        #expect(result == ct)
    }

    // MARK: - makeTypeVarBySymbol

    @Test
    func testMakeTypeVarBySymbolCreatesCorrectMapping() {
        let ts = TypeSystem()
        let syms = [SymbolID(rawValue: 10), SymbolID(rawValue: 20)]
        let mapping = ts.makeTypeVarBySymbol(syms)
        #expect(mapping.count == 2)
        #expect(mapping[syms[0]]?.rawValue == 0)
        #expect(mapping[syms[1]]?.rawValue == 1)
    }

    // MARK: - isNominalSubtypeSymbol

    @Test
    func testIsNominalSubtypeSymbolTransitive() {
        let ts = TypeSystem()
        let grandparent = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        let child = SymbolID(rawValue: 2)
        ts.setNominalDirectSupertypes([grandparent], for: parent)
        ts.setNominalDirectSupertypes([parent], for: child)

        #expect(ts.isNominalSubtypeSymbol(child, of: grandparent))
        #expect(!(ts.isNominalSubtypeSymbol(grandparent, of: child)))
    }

    @Test
    func testIsNominalSubtypeSymbolSelf() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        #expect(ts.isNominalSubtypeSymbol(sym, of: sym))
    }

    // MARK: - normalizedNominalVariances

    @Test
    func testNormalizedNominalVariancesPadsWithInvariant() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        ts.setNominalTypeParameterVariances([.out], for: sym)
        let variances = ts.normalizedNominalVariances(for: sym, arity: 3)
        #expect(variances == [.out, .invariant, .invariant])
    }

    @Test
    func testNormalizedNominalVariancesEmptyReturnsAllInvariant() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let variances = ts.normalizedNominalVariances(for: sym, arity: 2)
        #expect(variances == [.invariant, .invariant])
    }

    @Test
    func testNormalizedNominalVariancesTruncatesExcess() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        ts.setNominalTypeParameterVariances([.out, .in, .invariant], for: sym)
        let variances = ts.normalizedNominalVariances(for: sym, arity: 2)
        #expect(variances == [.out, .in])
    }

    // MARK: - Class Subtyping with type args

    @Test
    func testClassSubtypingWithStarProjection() {
        let ts = TypeSystem()
        let parentSym = SymbolID(rawValue: 0)
        let childSym = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parentSym], for: childSym)

        let intType = ts.make(.primitive(.int, .nonNull))
        let child = ts.make(.classType(ClassType(classSymbol: childSym, args: [.invariant(intType)])))
        let parentStar = ts.make(.classType(ClassType(classSymbol: parentSym, args: [.star])))
        #expect(ts.isSubtype(child, parentStar))
    }

    @Test
    func testClassSubtypingSameSymbolDifferentArgCount() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let intType = ts.make(.primitive(.int, .nonNull))
        let withArg = ts.make(.classType(ClassType(classSymbol: sym, args: [.invariant(intType)])))
        let withoutArg = ts.make(.classType(ClassType(classSymbol: sym, args: [])))
        #expect(!(ts.isSubtype(withArg, withoutArg)))
    }

    // MARK: - Projection Subtyping

    @Test
    func testProjectionSubtypeStarAcceptsAll() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.isProjectionSubtype(.invariant(intType), .star))
        #expect(ts.isProjectionSubtype(.out(intType), .star))
        #expect(ts.isProjectionSubtype(.in(intType), .star))
    }

    @Test
    func testProjectionSubtypeInvalidRejectsBoth() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(!(ts.isProjectionSubtype(.invalid, .invariant(intType))))
        #expect(!(ts.isProjectionSubtype(.invariant(intType), .invalid)))
    }

    @Test
    func testProjectionSubtypeStarIsNotSubtypeOfConcrete() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(!(ts.isProjectionSubtype(.star, .invariant(intType))))
    }

    @Test
    func testComposedProjectionOutVariance() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .out, useSite: .invariant(intType))
        if case let .out(t) = result {
            #expect(t == intType)
        } else {
            Issue.record("Expected .out projection")
        }
    }

    @Test
    func testComposedProjectionInVariance() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .in, useSite: .invariant(intType))
        if case let .in(t) = result {
            #expect(t == intType)
        } else {
            Issue.record("Expected .in projection")
        }
    }

    @Test
    func testComposedProjectionOutWithInReturnsInvalid() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .out, useSite: .in(intType))
        if case .invalid = result {
            // Expected
        } else {
            Issue.record("Expected .invalid from out + in")
        }
    }

    @Test
    func testComposedProjectionInWithOutReturnsInvalid() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .in, useSite: .out(intType))
        if case .invalid = result {
            // Expected
        } else {
            Issue.record("Expected .invalid from in + out")
        }
    }

    @Test
    func testComposedProjectionInWithInReturnsOut() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let result = ts.composedProjection(declarationVariance: .in, useSite: .in(intType))
        if case let .out(t) = result {
            #expect(t == intType)
        } else {
            Issue.record("Expected .out from in + in")
        }
    }
}
