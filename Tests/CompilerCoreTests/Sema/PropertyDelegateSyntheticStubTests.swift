#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct PropertyDelegateSyntheticStubTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    @Test func testObservablePropertySurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let propertiesFQName = ["kotlin", "properties"].map { interner.intern($0) }
        let observableFQName = propertiesFQName + [interner.intern("ObservableProperty")]
        let readWriteFQName = propertiesFQName + [interner.intern("ReadWriteProperty")]
        let readOnlyFQName = propertiesFQName + [interner.intern("ReadOnlyProperty")]
        let kPropertyFQName = ["kotlin", "reflect", "KProperty"].map { interner.intern($0) }

        let observableSymbol = try #require(sema.symbols.lookup(fqName: observableFQName))
        let readWriteSymbol = try #require(sema.symbols.lookup(fqName: readWriteFQName))
        let readOnlySymbol = try #require(sema.symbols.lookup(fqName: readOnlyFQName))
        let kPropertySymbol = try #require(sema.symbols.lookup(fqName: kPropertyFQName))
        let observableInfo = try #require(sema.symbols.symbol(observableSymbol))
        let readWriteInfo = try #require(sema.symbols.symbol(readWriteSymbol))
        let readOnlyInfo = try #require(sema.symbols.symbol(readOnlySymbol))
        #expect(observableInfo.kind == .class)
        #expect(observableInfo.flags.contains(.abstractType))
        #expect(sema.symbols.directSupertypes(for: observableSymbol) == [readWriteSymbol])
        #expect(!readWriteInfo.flags.contains(.synthetic))
        #expect(!readOnlyInfo.flags.contains(.synthetic))
        #expect(readOnlyInfo.declSite != nil)
        try assertNominalTypeParameters(
            for: readWriteSymbol,
            names: ["T", "V"],
            variances: [.in, .invariant],
            sema: sema,
            interner: interner
        )
        try assertNominalTypeParameters(
            for: readOnlySymbol,
            names: ["T", "V"],
            variances: [.in, .out],
            sema: sema,
            interner: interner
        )

        let typeParams = sema.types.nominalTypeParameterSymbols(for: observableSymbol)
        #expect(typeParams.count == 1)
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        #expect(
            sema.symbols.supertypeTypeArgs(for: observableSymbol, supertype: readWriteSymbol) == [.in(sema.types.nullableAnyType), .invariant(valueType)]
        )

        let observableType = sema.types.make(.classType(ClassType(
            classSymbol: observableSymbol,
            args: [.invariant(valueType)],
            nullability: .nonNull
        )))
        let kPropertyType = sema.types.make(.classType(ClassType(
            classSymbol: kPropertySymbol,
            args: [.star],
            nullability: .nonNull
        )))

        let initSymbol = try #require(sema.symbols.lookup(fqName: observableFQName + [interner.intern("<init>")]))
        let initSignature = try #require(sema.symbols.functionSignature(for: initSymbol))
        #expect(initSignature.parameterTypes == [valueType])
        #expect(initSignature.returnType == observableType)
        #expect(initSignature.typeParameterSymbols == typeParams)
        #expect(initSignature.classTypeParameterCount == 1)

        try assertMember(
            named: "beforeChange",
            visibility: .protected,
            requiredFlags: [.openType],
            parameterTypes: [kPropertyType, valueType, valueType],
            returnType: sema.types.booleanType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
        try assertMember(
            named: "afterChange",
            visibility: .protected,
            requiredFlags: [.openType],
            parameterTypes: [kPropertyType, valueType, valueType],
            returnType: sema.types.unitType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
        try assertMember(
            named: "getValue",
            requiredFlags: [.operatorFunction, .overrideMember, .openType],
            parameterTypes: [sema.types.nullableAnyType, kPropertyType],
            returnType: valueType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
        try assertMember(
            named: "setValue",
            requiredFlags: [.operatorFunction, .overrideMember, .openType],
            parameterTypes: [sema.types.nullableAnyType, kPropertyType, valueType],
            returnType: sema.types.unitType,
            ownerFQName: observableFQName,
            ownerType: observableType,
            typeParams: typeParams,
            sema: sema,
            interner: interner
        )
    }

    @Test func testDelegatesObservableAndVetoableStayBackedByReadWriteProperty() throws {
        let (sema, interner) = try sharedSema()
        let propertiesFQName = ["kotlin", "properties"].map { interner.intern($0) }
        let delegatesFQName = propertiesFQName + [interner.intern("Delegates")]
        let readWriteFQName = propertiesFQName + [interner.intern("ReadWriteProperty")]
        let delegatesSymbol = try #require(sema.symbols.lookup(fqName: delegatesFQName))
        let readWriteSymbol = try #require(sema.symbols.lookup(fqName: readWriteFQName))
        let delegatesType = sema.types.make(.classType(ClassType(
            classSymbol: delegatesSymbol,
            args: [],
            nullability: .nonNull
        )))
        // BUG-147: the factories are generic in the delegated property's value
        // type and take (initialValue, onChange) so that both
        // `by Delegates.observable(v) { ... }` (property position, trailing
        // lambda not counted as an argument — hence the defaulted callback) and
        // a call inside a function body resolve, and so that the property type
        // can be read back off `ReadWriteProperty<Any?, T>`.
        for memberName in ["observable", "vetoable"] {
            let memberSymbol = try #require(sema.symbols.lookup(fqName: delegatesFQName + [interner.intern(memberName)]))
            let signature = try #require(sema.symbols.functionSignature(for: memberSymbol))
            #expect(signature.receiverType == delegatesType)

            let valueTypeParam = try #require(signature.typeParameterSymbols.first)
            let valueType = sema.types.make(.typeParam(TypeParamType(
                symbol: valueTypeParam,
                nullability: .nonNull
            )))
            #expect(signature.parameterTypes.count == 2)
            #expect(signature.parameterTypes.first == valueType)
            #expect(signature.valueParameterHasDefaultValues == [false, true])
            guard case let .functionType(onChange) = sema.types.kind(of: signature.parameterTypes[1]) else {
                Issue.record("onChange parameter should be a function type")
                return
            }
            #expect(onChange.params.count == 3)
            #expect(
                onChange.returnType == (memberName == "vetoable" ? sema.types.booleanType : sema.types.unitType)
            )

            let expectedReturnType = sema.types.make(.classType(ClassType(
                classSymbol: readWriteSymbol,
                args: [.in(sema.types.makeNullable(sema.types.anyType)), .invariant(valueType)],
                nullability: .nonNull
            )))
            #expect(signature.returnType == expectedReturnType)
        }
    }

    @Test func testRootLazyAndLazyOfSurfaceAreRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinFQName = ["kotlin"].map { interner.intern($0) }
        let lazyFQName = kotlinFQName + [interner.intern("Lazy")]
        let lazySymbol = try #require(sema.symbols.lookup(fqName: lazyFQName))
        try assertNominalTypeParameters(
            for: lazySymbol,
            names: ["T"],
            variances: [.out],
            sema: sema,
            interner: interner
        )

        let lazyTypeParams = sema.types.nominalTypeParameterSymbols(for: lazySymbol)
        #expect(lazyTypeParams.count == 1)
        let lazyTParamSymbol = try #require(lazyTypeParams.first)
        let lazyTParamType = sema.types.make(.typeParam(TypeParamType(symbol: lazyTParamSymbol, nullability: .nonNull)))
        let lazyType = sema.types.make(.classType(ClassType(classSymbol: lazySymbol, args: [.invariant(lazyTParamType)], nullability: .nonNull)))

        let valueSymbol = try #require(sema.symbols.lookup(fqName: lazyFQName + [interner.intern("value")]))
        let valueInfo = try #require(sema.symbols.symbol(valueSymbol))
        #expect(valueInfo.kind == .property)
        #expect(!valueInfo.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: valueSymbol) == lazySymbol)
        #expect(sema.symbols.propertyType(for: valueSymbol) == lazyTParamType)

        let isInitializedSymbol = try #require(
            sema.symbols.lookup(fqName: lazyFQName + [interner.intern("isInitialized")])
        )
        let isInitializedInfo = try #require(sema.symbols.symbol(isInitializedSymbol))
        #expect(isInitializedInfo.kind == .function)
        #expect(!isInitializedInfo.flags.contains(.synthetic))
        let isInitializedSignature = try #require(sema.symbols.functionSignature(for: isInitializedSymbol))
        #expect(isInitializedSignature.receiverType == lazyType)
        #expect(isInitializedSignature.parameterTypes == [])
        #expect(isInitializedSignature.returnType == sema.types.booleanType)
        #expect(isInitializedSignature.typeParameterSymbols == lazyTypeParams)
        #expect(isInitializedSignature.classTypeParameterCount == 1)

        let lazyOfSymbol = try #require(sema.symbols.lookup(fqName: kotlinFQName + [interner.intern("lazyOf")]))
        let lazyOfInfo = try #require(sema.symbols.symbol(lazyOfSymbol))
        #expect(sema.symbols.externalLinkName(for: lazyOfSymbol) == nil)
        #expect(!lazyOfInfo.flags.contains(.synthetic))
        let lazyOfSignature = try #require(sema.symbols.functionSignature(for: lazyOfSymbol))
        #expect(lazyOfSignature.parameterTypes.count == 1)
        #expect(lazyOfSignature.valueParameterHasDefaultValues == [false])
        #expect(lazyOfSignature.valueParameterIsVararg == [false])
        #expect(lazyOfSignature.typeParameterSymbols.count == 1)

        guard case let .classType(returnType) = sema.types.kind(of: lazyOfSignature.returnType),
              returnType.args.count == 1,
              case let .invariant(returnArgument) = returnType.args[0]
        else {
            Issue.record("Expected lazyOf to return Lazy<T>"); return
        }
        #expect(returnType.classSymbol == lazySymbol)
        #expect(returnArgument == lazyOfSignature.parameterTypes[0])
    }

    private func assertMember(
        named name: String,
        visibility: Visibility = .public,
        requiredFlags: SymbolFlags,
        parameterTypes: [TypeID],
        returnType: TypeID,
        ownerFQName: [InternedString],
        ownerType: TypeID,
        typeParams: [SymbolID],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let symbol = try #require(
            sema.symbols.lookup(fqName: ownerFQName + [interner.intern(name)])
        )
        let info = try #require(sema.symbols.symbol(symbol))
        #expect(info.visibility == visibility)
        #expect(info.flags.isSuperset(of: requiredFlags))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.receiverType == ownerType)
        #expect(signature.parameterTypes == parameterTypes)
        #expect(signature.returnType == returnType)
        #expect(signature.typeParameterSymbols == typeParams)
        #expect(signature.classTypeParameterCount == 1)
    }

    private func assertNominalTypeParameters(
        for symbol: SymbolID,
        names: [String],
        variances: [TypeVariance],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: symbol)
        #expect(typeParameters.count == names.count)
        let resolvedNames = try typeParameters.map { parameterSymbol in
            try interner.resolve(#require(sema.symbols.symbol(parameterSymbol)?.name))
        }
        #expect(resolvedNames == names)
        #expect(sema.types.nominalTypeParameterVariances(for: symbol) == variances)
    }
}
#endif
