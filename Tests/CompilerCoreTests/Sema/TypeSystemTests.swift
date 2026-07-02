@testable import CompilerCore
import Testing

@Suite
struct TypeSystemTests {
    // MARK: - Built-in Types

    @Test
    func testBuiltInTypesArePreInitialized() {
        let ts = TypeSystem()
        #expect(ts.kind(of: ts.errorType) == .error)
        #expect(ts.kind(of: ts.unitType) == .unit)
        #expect(ts.kind(of: ts.nothingType) == .nothing(.nonNull))
        #expect(ts.kind(of: ts.nullableNothingType) == .nothing(.nullable))
        #expect(ts.kind(of: ts.anyType) == .any(.nonNull))
        #expect(ts.kind(of: ts.nullableAnyType) == .any(.nullable))
        // makeNullable / makeNonNullable round-trip for Nothing
        #expect(ts.makeNullable(ts.nothingType) == ts.nullableNothingType)
        #expect(ts.makeNonNullable(ts.nullableNothingType) == ts.nothingType)
    }

    @Test
    func testBuiltInTypeIDsAreDistinct() {
        let ts = TypeSystem()
        let ids: [TypeID] = [ts.errorType, ts.unitType, ts.nothingType, ts.anyType, ts.nullableAnyType]
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == 5)
    }

    // MARK: - make / kind

    @Test
    func testMakeDeduplicatesIdenticalTypes() {
        let ts = TypeSystem()
        let intA = ts.make(.primitive(.int, .nonNull))
        let intB = ts.make(.primitive(.int, .nonNull))
        #expect(intA == intB)
    }

    @Test
    func testMakeDistinguishesDifferentNullability() {
        let ts = TypeSystem()
        let nonNull = ts.make(.primitive(.int, .nonNull))
        let nullable = ts.make(.primitive(.int, .nullable))
        #expect(nonNull != nullable)
    }

    @Test
    func testMakeAllPrimitiveTypes() {
        let ts = TypeSystem()
        let primitives: [PrimitiveType] = [.boolean, .char, .int, .long, .float, .double]
        for prim in primitives {
            let id = ts.make(.primitive(prim, .nonNull))
            #expect(ts.kind(of: id) == .primitive(prim, .nonNull))
        }
        #expect(ts.stringType != TypeID.invalid)
    }

    @Test
    func testKindReturnsErrorForInvalidID() {
        let ts = TypeSystem()
        #expect(ts.kind(of: TypeID(rawValue: -1)) == .error)
        #expect(ts.kind(of: TypeID(rawValue: 99999)) == .error)
    }

    @Test
    func testMakeClassType() {
        let ts = TypeSystem()
        let classType = ClassType(classSymbol: SymbolID(rawValue: 0), args: [], nullability: .nonNull)
        let id = ts.make(.classType(classType))
        if case let .classType(ct) = ts.kind(of: id) {
            #expect(ct.classSymbol == SymbolID(rawValue: 0))
            #expect(ct.nullability == .nonNull)
        } else {
            Issue.record("Expected classType")
        }
    }

    @Test
    func testMakeTypeParam() {
        let ts = TypeSystem()
        let tp = TypeParamType(symbol: SymbolID(rawValue: 1), nullability: .nullable)
        let id = ts.make(.typeParam(tp))
        if case let .typeParam(result) = ts.kind(of: id) {
            #expect(result.symbol == SymbolID(rawValue: 1))
            #expect(result.nullability == .nullable)
        } else {
            Issue.record("Expected typeParam")
        }
    }

    @Test
    func testMakeFunctionType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let ft = FunctionType(
            receiver: nil,
            params: [intType],
            returnType: intType,
            isSuspend: false,
            nullability: .nonNull
        )
        let id = ts.make(.functionType(ft))
        if case let .functionType(result) = ts.kind(of: id) {
            #expect(result.params.count == 1)
            #expect(result.receiver == nil)
            #expect(!(result.isSuspend))
        } else {
            Issue.record("Expected functionType")
        }
    }

    @Test
    func testMakeIntersectionType() {
        let ts = TypeSystem()
        let a = ts.make(.primitive(.int, .nonNull))
        let b = ts.stringType
        let id = ts.make(.intersection([a, b]))
        if case let .intersection(parts) = ts.kind(of: id) {
            #expect(parts.count == 2)
            #expect(parts.contains(a))
            #expect(parts.contains(b))
        } else {
            Issue.record("Expected intersection")
        }
    }

    // MARK: - Subtyping

    @Test
    func testSameTypeIsSubtype() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.isSubtype(intType, intType))
    }

    @Test
    func testNothingIsSubtypeOfEverything() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.isSubtype(ts.nothingType, intType))
        #expect(ts.isSubtype(ts.nothingType, ts.anyType))
        #expect(ts.isSubtype(ts.nothingType, ts.nullableAnyType))
    }

    @Test
    func testErrorIsSubtypeOfAnything() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.isSubtype(ts.errorType, intType))
        #expect(ts.isSubtype(intType, ts.errorType))
    }

    @Test
    func testEverythingIsSubtypeOfNullableAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nullableInt = ts.make(.primitive(.int, .nullable))
        #expect(ts.isSubtype(intType, ts.nullableAnyType))
        #expect(ts.isSubtype(nullableInt, ts.nullableAnyType))
    }

    @Test
    func testNonNullIsSubtypeOfAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.isSubtype(intType, ts.anyType))
    }

    @Test
    func testNullableIsNotSubtypeOfNonNullAny() {
        let ts = TypeSystem()
        let nullableInt = ts.make(.primitive(.int, .nullable))
        #expect(!(ts.isSubtype(nullableInt, ts.anyType)))
    }

    @Test
    func testNonNullAnyIsSubtypeOfNullableAny() {
        let ts = TypeSystem()
        #expect(ts.isSubtype(ts.anyType, ts.nullableAnyType))
    }

    @Test
    func testNullabilitySubtype() {
        let ts = TypeSystem()
        let nonNull = ts.make(.primitive(.int, .nonNull))
        let nullable = ts.make(.primitive(.int, .nullable))
        #expect(ts.isSubtype(nonNull, nullable))
        #expect(!(ts.isSubtype(nullable, nonNull)))
    }

    @Test
    func testDifferentPrimitivesNotSubtype() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.stringType
        #expect(!(ts.isSubtype(intType, stringType)))
    }

    @Test
    func testFunctionSubtypingParamCountMismatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let f1 = ts.make(.functionType(FunctionType(params: [intType], returnType: intType)))
        let f2 = ts.make(.functionType(FunctionType(params: [intType, intType], returnType: intType)))
        #expect(!(ts.isSubtype(f1, f2)))
    }

    @Test
    func testFunctionSubtypingSuspendMismatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let suspendFn = ts.make(.functionType(FunctionType(params: [], returnType: intType, isSuspend: true)))
        let normalFn = ts.make(.functionType(FunctionType(params: [], returnType: intType, isSuspend: false)))
        #expect(!(ts.isSubtype(suspendFn, normalFn)))
    }

    @Test
    func testFunctionSubtypingReceiverMismatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let withReceiver = ts.make(.functionType(FunctionType(receiver: intType, params: [], returnType: intType)))
        let withoutReceiver = ts.make(.functionType(FunctionType(params: [], returnType: intType)))
        #expect(!(ts.isSubtype(withReceiver, withoutReceiver)))
    }

    @Test
    func testFunctionSubtypingContravariantParams() {
        let ts = TypeSystem()
        let anyNonNull = ts.anyType
        let intType = ts.make(.primitive(.int, .nonNull))
        // (Any) -> Int <: (Int) -> Int  -- param contravariance
        let fAny = ts.make(.functionType(FunctionType(params: [anyNonNull], returnType: intType)))
        let fInt = ts.make(.functionType(FunctionType(params: [intType], returnType: intType)))
        #expect(ts.isSubtype(fAny, fInt))
        #expect(!(ts.isSubtype(fInt, fAny)))
    }

    @Test
    func testFunctionSubtypingCovariantReturn() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let anyNonNull = ts.anyType
        // () -> Int <: () -> Any
        let fRetInt = ts.make(.functionType(FunctionType(params: [], returnType: intType)))
        let fRetAny = ts.make(.functionType(FunctionType(params: [], returnType: anyNonNull)))
        #expect(ts.isSubtype(fRetInt, fRetAny))
    }

    @Test
    func testClassSubtypingWithNominalHierarchy() {
        let ts = TypeSystem()
        let parentSymbol = SymbolID(rawValue: 0)
        let childSymbol = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parentSymbol], for: childSymbol)

        let parentType = ts.make(.classType(ClassType(classSymbol: parentSymbol)))
        let childType = ts.make(.classType(ClassType(classSymbol: childSymbol)))
        #expect(ts.isSubtype(childType, parentType))
        #expect(!(ts.isSubtype(parentType, childType)))
    }

    @Test
    func testAnnotationSubtyping() {
        let ts = TypeSystem()
        let st = SymbolTable()
        let interner = StringInterner()
        ts.symbolTable = st

        let annoInterfaceSym = st.define(kind: .interface, name: interner.intern("Annotation"), fqName: [interner.intern("kotlin"), interner.intern("Annotation")], declSite: nil, visibility: .public)
        ts.annotationInterfaceSymbol = annoInterfaceSym
        let annotationType = ts.make(.classType(ClassType(classSymbol: annoInterfaceSym)))
        let nullableAnnotationType = ts.make(.classType(ClassType(classSymbol: annoInterfaceSym, args: [], nullability: .nullable)))

        let annoSymbol = st.define(kind: .annotationClass, name: interner.intern("MyAnnotation"), fqName: [interner.intern("MyAnnotation")], declSite: nil, visibility: .public)

        let annoType = ts.make(.classType(ClassType(classSymbol: annoSymbol)))
        let nullableAnnoType = ts.make(.classType(ClassType(classSymbol: annoSymbol, args: [], nullability: .nullable)))

        // Annotation class <: Annotation
        #expect(ts.isSubtype(annoType, annotationType))
        #expect(ts.isSubtype(nullableAnnoType, nullableAnnotationType))

        // Annotation <: Any
        #expect(ts.isSubtype(annotationType, ts.anyType))

        // Normal class is NOT <: Annotation
        let classSymbol = st.define(kind: .class, name: interner.intern("MyClass"), fqName: [interner.intern("MyClass")], declSite: nil, visibility: .public)
        let classType = ts.make(.classType(ClassType(classSymbol: classSymbol)))
        #expect(!(ts.isSubtype(classType, annotationType)))
        #expect(!(ts.isSubtype(nullableAnnotationType, annotationType)))
        #expect(!(ts.isSubtype(nullableAnnoType, annotationType)))

        // Nothing <: Annotation
        #expect(ts.isSubtype(ts.nothingType, annotationType))
    }

    @Test
    func testIntersectionSubtypingAllPartsSubtype() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let intersect = ts.make(.intersection([intType]))
        #expect(ts.isSubtype(intersect, ts.anyType))
    }

    @Test
    func testSubtypeOfIntersectionContainsMatch() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let intersect = ts.make(.intersection([intType, ts.anyType]))
        #expect(ts.isSubtype(intType, intersect))
    }

    // MARK: - LUB / GLB

    @Test
    func testLubOfEmptyReturnsError() {
        let ts = TypeSystem()
        #expect(ts.lub([]) == ts.errorType)
    }

    @Test
    func testLubOfSingleTypeReturnsThatType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.lub([intType]) == intType)
    }

    @Test
    func testLubOfIdenticalTypesReturnsThatType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.lub([intType, intType, intType]) == intType)
    }

    @Test
    func testLubOfMixedTypesReturnsAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.stringType
        #expect(ts.lub([intType, stringType]) == ts.anyType)
    }

    @Test
    func testLubFiltersNothingAndError() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.lub([intType, ts.nothingType]) == intType)
        #expect(ts.lub([intType, ts.errorType]) == intType)
    }

    @Test
    func testLubOfOnlyNothingReturnsNothing() {
        let ts = TypeSystem()
        #expect(ts.lub([ts.nothingType]) == ts.nothingType)
    }

    @Test
    func testLubOfNullableTypesReturnsNullableAny() {
        let ts = TypeSystem()
        let nullableInt = ts.make(.primitive(.int, .nullable))
        let nullableString = ts.makeNullable(ts.stringType)
        #expect(ts.lub([nullableInt, nullableString]) == ts.nullableAnyType)
    }

    @Test
    func testGlbOfEmptyReturnsError() {
        let ts = TypeSystem()
        #expect(ts.glb([]) == ts.errorType)
    }

    @Test
    func testGlbOfIdenticalReturnsType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.glb([intType, intType]) == intType)
    }

    @Test
    func testGlbContainingNothingReturnsNothing() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        #expect(ts.glb([intType, ts.nothingType]) == ts.nothingType)
    }

    @Test
    func testGlbOfDifferentTypesReturnsIntersection() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.stringType
        let result = ts.glb([intType, stringType])
        if case let .intersection(parts) = ts.kind(of: result) {
            #expect(parts.count == 2)
        } else {
            Issue.record("Expected intersection type from glb")
        }
    }

    // MARK: - Nominal Supertypes

    @Test
    func testSetAndGetNominalDirectSupertypes() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parent], for: sym)
        #expect(ts.directNominalSupertypes(for: sym) == [parent])
    }

    @Test
    func testDirectNominalSupertypesReturnsEmptyForUnknown() {
        let ts = TypeSystem()
        #expect(ts.directNominalSupertypes(for: SymbolID(rawValue: 99)) == [])
    }

    @Test
    func testSetNominalDirectSupertypesDeduplicates() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        let parent = SymbolID(rawValue: 1)
        ts.setNominalDirectSupertypes([parent, parent, parent], for: sym)
        #expect(ts.directNominalSupertypes(for: sym).count == 1)
    }

    // MARK: - Type Parameter Variances

    @Test
    func testSetAndGetTypeParameterVariances() {
        let ts = TypeSystem()
        let sym = SymbolID(rawValue: 0)
        ts.setNominalTypeParameterVariances([.out, .in, .invariant], for: sym)
        #expect(ts.nominalTypeParameterVariances(for: sym) == [.out, .in, .invariant])
    }

    @Test
    func testTypeParameterVariancesReturnsEmptyForUnknown() {
        let ts = TypeSystem()
        #expect(ts.nominalTypeParameterVariances(for: SymbolID(rawValue: 42)) == [])
    }

    // MARK: - Platform Type (T!)

    @Test
    func testPlatformTypeMakeAndKind() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        #expect(ts.kind(of: platformInt) == .primitive(.int, .platformType))
    }

    @Test
    func testPlatformTypeNullabilityOf() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        #expect(ts.nullability(of: platformInt) == .platformType)
    }

    @Test
    func testPlatformTypeIsSubtypeOfNonNull() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        let nonNullInt = ts.make(.primitive(.int, .nonNull))
        #expect(ts.isSubtype(platformInt, nonNullInt))
    }

    @Test
    func testPlatformTypeIsSubtypeOfNullable() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        let nullableInt = ts.make(.primitive(.int, .nullable))
        #expect(ts.isSubtype(platformInt, nullableInt))
    }

    @Test
    func testNonNullIsSubtypeOfPlatformType() {
        let ts = TypeSystem()
        let nonNullInt = ts.make(.primitive(.int, .nonNull))
        let platformInt = ts.make(.primitive(.int, .platformType))
        #expect(ts.isSubtype(nonNullInt, platformInt))
    }

    @Test
    func testNullableIsSubtypeOfPlatformType() {
        let ts = TypeSystem()
        let nullableInt = ts.make(.primitive(.int, .nullable))
        let platformInt = ts.make(.primitive(.int, .platformType))
        #expect(ts.isSubtype(nullableInt, platformInt))
    }

    @Test
    func testPlatformTypeIsNotDefinitelyNonNull() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        #expect(!(ts.isDefinitelyNonNull(platformInt)))
    }

    @Test
    func testWithNullabilityPlatformType() {
        let ts = TypeSystem()
        let platformAny = ts.withNullability(.platformType, for: ts.anyType)
        #expect(ts.nullability(of: platformAny) == .platformType)
    }

    @Test
    func testMakeNullableOnPlatformType() {
        let ts = TypeSystem()
        let platformInt = ts.make(.primitive(.int, .platformType))
        let nullableInt = ts.makeNullable(platformInt)
        #expect(ts.nullability(of: nullableInt) == .nullable)
    }

    @Test
    func testWithNullabilityPlatformTypeForNothingNormalizesToNullableNothing() {
        let types = TypeSystem()
        let normalized = types.withNullability(.platformType, for: types.nothingType)
        #expect(normalized == types.nullableNothingType)
        #expect(types.kind(of: normalized) == .nothing(.nullable))
    }

    @Test
    func testMakeNothingPlatformTypeNormalizesToNullableNothing() {
        let types = TypeSystem()
        let normalized = types.make(.nothing(.platformType))
        #expect(normalized == types.nullableNothingType)
        #expect(types.kind(of: normalized) == .nothing(.nullable))
    }

    @Test
    func testNothingNullableIsSubtypeOfPlatformType() {
        let types = TypeSystem()
        let platformInt = types.make(.primitive(.int, .platformType))
        let platformAny = types.withNullability(.platformType, for: types.anyType)
        #expect(types.isSubtype(types.nullableNothingType, platformInt))
        #expect(types.isSubtype(types.nullableNothingType, platformAny))
    }

    // MARK: - KClass<T> (REFL-001)

    @Test
    func testMakeKClassType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassInt = ts.makeKClassType(argument: intType)
        if case let .kClassType(kc) = ts.kind(of: kClassInt) {
            #expect(kc.argument == intType)
            #expect(kc.nullability == .nonNull)
        } else {
            Issue.record("Expected kClassType")
        }
    }

    @Test
    func testMakeKClassTypeDeduplicates() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let a = ts.makeKClassType(argument: intType)
        let b = ts.makeKClassType(argument: intType)
        #expect(a == b)
    }

    @Test
    func testMakeKClassTypeDistinctArguments() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.stringType
        let kClassInt = ts.makeKClassType(argument: intType)
        let kClassString = ts.makeKClassType(argument: stringType)
        #expect(kClassInt != kClassString)
    }

    @Test
    func testKClassTypeNullability() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nonNull = ts.makeKClassType(argument: intType, nullability: .nonNull)
        let nullable = ts.makeKClassType(argument: intType, nullability: .nullable)
        #expect(ts.isDefinitelyNonNull(nonNull))
        #expect(!(ts.isDefinitelyNonNull(nullable)))
        #expect(ts.nullability(of: nonNull) == .nonNull)
        #expect(ts.nullability(of: nullable) == .nullable)
    }

    @Test
    func testKClassTypeWithNullability() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nonNull = ts.makeKClassType(argument: intType)
        let nullable = ts.makeNullable(nonNull)
        #expect(nonNull != nullable)
        #expect(ts.nullability(of: nullable) == .nullable)
        // Round-trip back to non-null
        let backToNonNull = ts.makeNonNullable(nullable)
        #expect(backToNonNull == nonNull)
    }

    @Test
    func testKClassSubtypingSameArgument() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassA = ts.makeKClassType(argument: intType)
        let kClassB = ts.makeKClassType(argument: intType)
        #expect(ts.isSubtype(kClassA, kClassB))
    }

    @Test
    func testKClassSubtypingDifferentArguments() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.stringType
        let kClassInt = ts.makeKClassType(argument: intType)
        let kClassString = ts.makeKClassType(argument: stringType)
        // Even with covariance, unrelated arguments are not compatible.
        #expect(!(ts.isSubtype(kClassInt, kClassString)))
    }

    @Test
    func testKClassSubtypingIsCovariant() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassInt = ts.makeKClassType(argument: intType)
        let kClassAny = ts.makeKClassType(argument: ts.anyType)
        #expect(ts.isSubtype(kClassInt, kClassAny))
        #expect(!(ts.isSubtype(kClassAny, kClassInt)))
    }

    @Test
    func testKClassIsSubtypeOfAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassInt = ts.makeKClassType(argument: intType)
        #expect(ts.isSubtype(kClassInt, ts.anyType))
        #expect(ts.isSubtype(kClassInt, ts.nullableAnyType))
    }

    @Test
    func testKClassNullableSubtyping() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nonNull = ts.makeKClassType(argument: intType, nullability: .nonNull)
        let nullable = ts.makeKClassType(argument: intType, nullability: .nullable)
        // KClass<Int> <: KClass<Int>?
        #expect(ts.isSubtype(nonNull, nullable))
        // KClass<Int>? is NOT <: KClass<Int>
        #expect(!(ts.isSubtype(nullable, nonNull)))
    }

    @Test
    func testNothingNullableIsSubtypeOfNullableKClass() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nullableKClass = ts.makeKClassType(argument: intType, nullability: .nullable)
        #expect(ts.isSubtype(ts.nullableNothingType, nullableKClass))
    }

    @Test
    func testNothingNullableIsNotSubtypeOfNonNullKClass() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let nonNullKClass = ts.makeKClassType(argument: intType, nullability: .nonNull)
        #expect(!(ts.isSubtype(ts.nullableNothingType, nonNullKClass)))
    }

    @Test
    func testKClassTypeContainsTypeParam() {
        let ts = TypeSystem()
        let tpSymbol = SymbolID(rawValue: 42)
        let tpType = ts.make(.typeParam(TypeParamType(symbol: tpSymbol)))
        let kClassT = ts.makeKClassType(argument: tpType)
        #expect(ts.typeContainsTypeParam(kClassT, symbol: tpSymbol))
        #expect(!(ts.typeContainsTypeParam(kClassT, symbol: SymbolID(rawValue: 99))))
    }

    @Test
    func testRenderKClassType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassInt = ts.makeKClassType(argument: intType)
        #expect(ts.renderType(kClassInt) == "KClass<Int>")
    }

    @Test
    func testRenderNullableKClassType() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassInt = ts.makeKClassType(argument: intType, nullability: .nullable)
        #expect(ts.renderType(kClassInt) == "KClass<Int>?")
    }

    @Test
    func testSubstituteKClassTypeArgument() {
        let ts = TypeSystem()
        let tpSymbol = SymbolID(rawValue: 10)
        let tpType = ts.make(.typeParam(TypeParamType(symbol: tpSymbol)))
        let kClassT = ts.makeKClassType(argument: tpType)
        let intType = ts.make(.primitive(.int, .nonNull))

        let typeVarBySymbol = ts.makeTypeVarBySymbol([tpSymbol])
        let substitution: [TypeVarID: TypeID] = [TypeVarID(rawValue: 0): intType]

        let result = ts.substituteTypeParameters(
            in: kClassT,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
        // After substitution, should be KClass<Int>
        if case let .kClassType(kc) = ts.kind(of: result) {
            #expect(kc.argument == intType)
            #expect(kc.nullability == .nonNull)
        } else {
            Issue.record("Expected kClassType after substitution, got \(ts.kind(of: result))")
        }
    }

    // MARK: - REFL-001: KClass LUB tests

    @Test
    func testLubKClassSameArgument() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassInt1 = ts.makeKClassType(argument: intType)
        let kClassInt2 = ts.makeKClassType(argument: intType)
        // lub(KClass<Int>, KClass<Int>) == KClass<Int>
        let result = ts.lub([kClassInt1, kClassInt2])
        #expect(result == kClassInt1)
    }

    @Test
    func testLubKClassDifferentArguments() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let stringType = ts.stringType
        let kClassInt = ts.makeKClassType(argument: intType)
        let kClassString = ts.makeKClassType(argument: stringType)
        // lub(KClass<Int>, KClass<String>) should be KClass<lub(Int,String)>
        let result = ts.lub([kClassInt, kClassString])
        if case let .kClassType(kc) = ts.kind(of: result) {
            #expect(kc.nullability == .nonNull)
            // The inner argument should be a supertype of both Int and String
            #expect(
                ts.isSubtype(intType, kc.argument) && ts.isSubtype(stringType, kc.argument),
                "KClass argument should be a supertype of both Int and String"
            )
        } else {
            Issue.record("Expected kClassType for lub of two KClass types, got \(ts.renderType(result))")
        }
    }

    @Test
    func testLubKClassNullablePreserved() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassNonNull = ts.makeKClassType(argument: intType, nullability: .nonNull)
        let kClassNullable = ts.makeKClassType(argument: intType, nullability: .nullable)
        // lub(KClass<Int>, KClass<Int>?) == KClass<Int>?
        let result = ts.lub([kClassNonNull, kClassNullable])
        if case let .kClassType(kc) = ts.kind(of: result) {
            #expect(kc.argument == intType)
            #expect(kc.nullability == .nullable, "LUB of non-null and nullable KClass should be nullable")
        } else {
            Issue.record("Expected kClassType for lub, got \(ts.renderType(result))")
        }
    }

    @Test
    func testLubKClassAndNonKClassFallsToAny() {
        let ts = TypeSystem()
        let intType = ts.make(.primitive(.int, .nonNull))
        let kClassInt = ts.makeKClassType(argument: intType)
        // lub(KClass<Int>, Int) should fall back to Any? (not KClass)
        let result = ts.lub([kClassInt, intType])
        #expect(
            !({ if case .kClassType = ts.kind(of: result) { return true }; return false }()),
            "LUB of KClass and non-KClass should not be a KClass type"
        )
    }
}
