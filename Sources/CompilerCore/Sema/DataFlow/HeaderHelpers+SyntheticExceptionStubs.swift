
extension DataFlowSemaPhase {
    func registerSyntheticExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinPkg: [InternedString]
    ) {
        let throwableSymbol = ensureClassSymbol(
            named: "Throwable",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let kotlinTextPkg = ensurePackage(path: ["kotlin", "text"], symbols: symbols, interner: interner)
        let characterCodingSymbol = ensureClassSymbol(
            named: "CharacterCodingException",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg) {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: characterCodingSymbol)
        }
        let kotlinIOPkg = ensurePackage(path: ["kotlin", "io"], symbols: symbols, interner: interner)
        let kotlinIOPkgSymbol = symbols.lookup(fqName: kotlinIOPkg)
        let noSuchFileSymbol = ensureClassSymbol(
            named: "NoSuchFileException",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPkgSymbol {
            symbols.setParentSymbol(kotlinIOPkgSymbol, for: noSuchFileSymbol)
        }
        // MARK: - kotlin.io.FileAlreadyExistsException (STDLIB-IO-TYPE-002)
        let fileAlreadyExistsExceptionSymbol = ensureClassSymbol(
            named: "FileAlreadyExistsException",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPkgSymbol {
            symbols.setParentSymbol(kotlinIOPkgSymbol, for: fileAlreadyExistsExceptionSymbol)
        }
        let runtimeExceptionSymbol = ensureClassSymbol(
            named: "RuntimeException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let uninitializedSymbol = ensureClassSymbol(
            named: "UninitializedPropertyAccessException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let nullPointerSymbol = ensureClassSymbol(
            named: "NullPointerException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let numberFormatSymbol = ensureClassSymbol(
            named: "NumberFormatException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let cancellationName = interner.intern("CancellationException")
        let canonicalCancellationFQName = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
            interner.intern("cancellation"),
            cancellationName,
        ]
        let rootCancellationFQName = kotlinPkg + [cancellationName]
        if let canonicalCancellationSymbol = symbols.lookup(fqName: canonicalCancellationFQName) {
            if symbols.lookup(fqName: rootCancellationFQName) == nil {
                let rootCancellationSymbol = symbols.define(
                    kind: .typeAlias,
                    name: cancellationName,
                    fqName: rootCancellationFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                let canonicalCancellationType = types.make(.classType(ClassType(
                    classSymbol: canonicalCancellationSymbol, args: [], nullability: .nonNull
                )))
                symbols.setTypeAliasUnderlyingType(canonicalCancellationType, for: rootCancellationSymbol)
            }
        } else {
            let cancellationSymbol = ensureClassSymbol(
                named: "CancellationException",
                in: kotlinPkg,
                symbols: symbols,
                interner: interner
            )
            symbols.setDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
            types.setNominalDirectSupertypes([exceptionSymbol], for: cancellationSymbol)
            let cancellationType = types.make(.classType(ClassType(
                classSymbol: cancellationSymbol, args: [], nullability: .nonNull
            )))
            symbols.setPropertyType(cancellationType, for: cancellationSymbol)
            registerSyntheticExceptionConstructors(
                ownerSymbol: cancellationSymbol,
                ownerType: cancellationType,
                symbols: symbols,
                types: types,
                interner: interner,
                includeMessageOverload: true,
                throwableSymbol: throwableSymbol
            )
        }
        let illegalArgumentSymbol = ensureClassSymbol(
            named: "IllegalArgumentException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let illegalStateSymbol = ensureClassSymbol(
            named: "IllegalStateException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let indexOutOfBoundsSymbol = ensureClassSymbol(
            named: "IndexOutOfBoundsException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let arrayIndexOutOfBoundsSymbol = ensureClassSymbol(
            named: "ArrayIndexOutOfBoundsException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let negativeArraySizeSymbol = ensureClassSymbol(
            named: "NegativeArraySizeException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let unsupportedOperationSymbol = ensureClassSymbol(
            named: "UnsupportedOperationException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let noSuchElementSymbol = ensureClassSymbol(
            named: "NoSuchElementException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let arithmeticSymbol = ensureClassSymbol(
            named: "ArithmeticException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let classCastSymbol = ensureClassSymbol(
            named: "ClassCastException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let noWhenBranchMatchedSymbol = ensureClassSymbol(
            named: "NoWhenBranchMatchedException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let concurrentModificationSymbol = ensureClassSymbol(
            named: "ConcurrentModificationException",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let errorSymbol = ensureClassSymbol(
            named: "Error",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        let assertionErrorSymbol = ensureClassSymbol(
            named: "AssertionError",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )

        symbols.setDirectSupertypes([throwableSymbol], for: exceptionSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: characterCodingSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: noSuchFileSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: fileAlreadyExistsExceptionSymbol)
        symbols.setDirectSupertypes([throwableSymbol], for: errorSymbol)
        symbols.setDirectSupertypes([errorSymbol], for: assertionErrorSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: runtimeExceptionSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: uninitializedSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: nullPointerSymbol)
        symbols.setDirectSupertypes([exceptionSymbol], for: numberFormatSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: illegalArgumentSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: illegalStateSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: indexOutOfBoundsSymbol)
        symbols.setDirectSupertypes([indexOutOfBoundsSymbol], for: arrayIndexOutOfBoundsSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: negativeArraySizeSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: unsupportedOperationSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: noSuchElementSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: arithmeticSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: classCastSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: noWhenBranchMatchedSymbol)
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: concurrentModificationSymbol)

        // Register nominal supertypes in TypeSystem for subtype checking
        types.setNominalDirectSupertypes([throwableSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: characterCodingSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: noSuchFileSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: fileAlreadyExistsExceptionSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: runtimeExceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: uninitializedSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: nullPointerSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: numberFormatSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: illegalArgumentSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: illegalStateSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: indexOutOfBoundsSymbol)
        types.setNominalDirectSupertypes([indexOutOfBoundsSymbol], for: arrayIndexOutOfBoundsSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: negativeArraySizeSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: unsupportedOperationSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: noSuchElementSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: arithmeticSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: classCastSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: noWhenBranchMatchedSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: concurrentModificationSymbol)
        types.setNominalDirectSupertypes([throwableSymbol], for: errorSymbol)
        types.setNominalDirectSupertypes([errorSymbol], for: assertionErrorSymbol)

        for symbol in [
            throwableSymbol,
            exceptionSymbol,
            characterCodingSymbol,
            noSuchFileSymbol,
            fileAlreadyExistsExceptionSymbol,
            runtimeExceptionSymbol,
            uninitializedSymbol,
            nullPointerSymbol,
            numberFormatSymbol,
            illegalArgumentSymbol,
            illegalStateSymbol,
            indexOutOfBoundsSymbol,
            arrayIndexOutOfBoundsSymbol,
            negativeArraySizeSymbol,
            unsupportedOperationSymbol,
            noSuchElementSymbol,
            arithmeticSymbol,
            classCastSymbol,
            noWhenBranchMatchedSymbol,
            concurrentModificationSymbol,
            errorSymbol,
            assertionErrorSymbol,
        ] {
            let type = types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
            symbols.setPropertyType(type, for: symbol)
        }

        registerSyntheticExceptionConstructors(
            ownerSymbol: exceptionSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: false,
            throwableSymbol: throwableSymbol
        )
        let characterCodingType = types.make(.classType(ClassType(
            classSymbol: characterCodingSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableStringType = types.makeNullable(types.stringType)
        registerSyntheticExceptionConstructor(
            ownerSymbol: characterCodingSymbol,
            ownerType: characterCodingType,
            parameters: [],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticExceptionConstructor(
            ownerSymbol: characterCodingSymbol,
            ownerType: characterCodingType,
            parameters: [("message", nullableStringType)],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        let noSuchFileType = types.make(.classType(ClassType(
            classSymbol: noSuchFileSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerSyntheticExceptionConstructor(
            ownerSymbol: noSuchFileSymbol,
            ownerType: noSuchFileType,
            parameters: [],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticExceptionConstructor(
            ownerSymbol: noSuchFileSymbol,
            ownerType: noSuchFileType,
            parameters: [("file", types.stringType)],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        // MARK: - FileAlreadyExistsException constructors (STDLIB-IO-TYPE-002)
        let fileAlreadyExistsExceptionType = types.make(.classType(ClassType(
            classSymbol: fileAlreadyExistsExceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerSyntheticExceptionConstructor(
            ownerSymbol: fileAlreadyExistsExceptionSymbol,
            ownerType: fileAlreadyExistsExceptionType,
            parameters: [],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticExceptionConstructor(
            ownerSymbol: fileAlreadyExistsExceptionSymbol,
            ownerType: fileAlreadyExistsExceptionType,
            parameters: [("file", types.stringType)],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: runtimeExceptionSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: runtimeExceptionSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true,
            throwableSymbol: throwableSymbol
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: uninitializedSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: uninitializedSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true,
            throwableSymbol: throwableSymbol
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: nullPointerSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: nullPointerSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: false,
            throwableSymbol: throwableSymbol
        )
        registerSyntheticExceptionConstructors(
            ownerSymbol: numberFormatSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: numberFormatSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner,
            includeMessageOverload: true,
            throwableSymbol: throwableSymbol
        )
        for exSymbol in [
            illegalArgumentSymbol,
            illegalStateSymbol,
            indexOutOfBoundsSymbol,
            unsupportedOperationSymbol,
            noSuchElementSymbol,
            arithmeticSymbol,
            classCastSymbol,
            errorSymbol,
            assertionErrorSymbol,
        ] {
            registerSyntheticExceptionConstructors(
                ownerSymbol: exSymbol,
                ownerType: types.make(.classType(ClassType(classSymbol: exSymbol, args: [], nullability: .nonNull))),
                symbols: symbols,
                types: types,
                interner: interner,
                includeMessageOverload: true,
                throwableSymbol: throwableSymbol
            )
        }
        registerSyntheticNullableExceptionConstructors(
            ownerSymbol: noWhenBranchMatchedSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: noWhenBranchMatchedSymbol, args: [], nullability: .nonNull))),
            throwableSymbol: throwableSymbol,
            externalLinkPrefix: "kk_no_when_branch_matched_exception",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNullableExceptionConstructors(
            ownerSymbol: concurrentModificationSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: concurrentModificationSymbol, args: [], nullability: .nonNull))),
            throwableSymbol: throwableSymbol,
            externalLinkPrefix: "kk_concurrent_modification_exception",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticArrayIndexOutOfBoundsExceptionConstructors(
            ownerSymbol: arrayIndexOutOfBoundsSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: arrayIndexOutOfBoundsSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNegativeArraySizeExceptionConstructors(
            ownerSymbol: negativeArraySizeSymbol,
            ownerType: types.make(.classType(ClassType(classSymbol: negativeArraySizeSymbol, args: [], nullability: .nonNull))),
            symbols: symbols,
            types: types,
            interner: interner
        )

        // MARK: - Throwable member properties (STDLIB-127)

        let throwableFQName = kotlinPkg + [interner.intern("Throwable")]

        // MARK: - Advanced exception features (STDLIB-EXCEPT-105)

        let throwableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol, args: [], nullability: .nonNull
        )))
        let throwableRef = SyntheticStubTypeRef.namedClass(["kotlin", "Throwable"])
        let nullableThrowableRef = SyntheticStubTypeRef.namedClass(
            ["kotlin", "Throwable"],
            nullability: .nullable
        )
        let throwableContext = SyntheticStubRegistrationContext(
            ownerFQName: throwableFQName,
            parentSymbol: throwableSymbol
        )
        registerSyntheticPropertyStubs(
            [
                // message: String?
                SyntheticPropertyStubSpec(
                    name: "message",
                    propertyType: .nullable(.string),
                    externalLinkName: "kk_throwable_message"
                ),
                // cause: Throwable?
                SyntheticPropertyStubSpec(
                    name: "cause",
                    propertyType: nullableThrowableRef,
                    externalLinkName: "kk_throwable_cause"
                ),
            ],
            context: throwableContext,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticFunctionStubs(
            [
                // stackTraceToString(): String
                SyntheticFunctionStubSpec(
                    name: "stackTraceToString",
                    externalLinkName: "kk_throwable_stackTraceToString",
                    receiverType: throwableRef,
                    returnType: .string
                ),
                // printStackTrace(): Unit
                SyntheticFunctionStubSpec(
                    name: "printStackTrace",
                    externalLinkName: "kk_throwable_printStackTrace",
                    receiverType: throwableRef,
                    returnType: .unit
                ),
                // initCause(cause: Throwable?): Throwable
                SyntheticFunctionStubSpec(
                    name: "initCause",
                    externalLinkName: "kk_throwable_initCause",
                    receiverType: throwableRef,
                    parameters: [
                        SyntheticStubParameterSpec(name: "cause", type: nullableThrowableRef),
                    ],
                    returnType: throwableRef
                ),
                // addSuppressed(exception: Throwable): Unit
                SyntheticFunctionStubSpec(
                    name: "addSuppressed",
                    externalLinkName: "kk_throwable_addSuppressed",
                    receiverType: throwableRef,
                    parameters: [
                        SyntheticStubParameterSpec(name: "exception", type: throwableRef),
                    ],
                    returnType: .unit
                ),
                // getSuppressed(): Array<Throwable>
                SyntheticFunctionStubSpec(
                    name: "getSuppressed",
                    externalLinkName: "kk_throwable_getSuppressed",
                    receiverType: throwableRef,
                    returnType: .typeID(makeSyntheticArrayType(
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        elementType: throwableType
                    ))
                ),
            ],
            context: throwableContext,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // suppressedExceptions: List<Throwable>
        let suppressedExceptionsName = interner.intern("suppressedExceptions")
        let suppressedExceptionsFQName = kotlinPkg + [suppressedExceptionsName]
        let suppressedExceptionsReturnType = makeSyntheticListType(
            symbols: symbols,
            types: types,
            interner: interner,
            elementType: throwableType
        )
        if let existing = symbols.lookupAll(fqName: suppressedExceptionsFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == throwableType
        }) {
            symbols.setPropertyType(suppressedExceptionsReturnType, for: existing)
            symbols.setExternalLinkName("kk_throwable_suppressedExceptions", for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: throwableType,
                        parameterTypes: [],
                        returnType: suppressedExceptionsReturnType
                    ),
                    for: getterSymbol
                )
                symbols.setExternalLinkName("kk_throwable_suppressedExceptions", for: getterSymbol)
            }
        } else {
            let propertySymbol = symbols.define(
                kind: .property,
                name: suppressedExceptionsName,
                fqName: suppressedExceptionsFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let packageSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(packageSymbol, for: propertySymbol)
            }
            symbols.setPropertyType(suppressedExceptionsReturnType, for: propertySymbol)
            symbols.setExtensionPropertyReceiverType(throwableType, for: propertySymbol)
            symbols.setExternalLinkName("kk_throwable_suppressedExceptions", for: propertySymbol)

            let getterSymbol = symbols.define(
                kind: .function,
                name: interner.intern("get"),
                fqName: suppressedExceptionsFQName + [interner.intern("$get")],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(propertySymbol, for: getterSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: throwableType,
                    parameterTypes: [],
                    returnType: suppressedExceptionsReturnType
                ),
                for: getterSymbol
            )
            symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
            symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
            symbols.setExternalLinkName("kk_throwable_suppressedExceptions", for: getterSymbol)
        }
    }

    private func makeSyntheticArrayType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let arrayFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("Array"),
        ]
        guard let arraySymbol = symbols.lookup(fqName: arrayFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    private func makeSyntheticListType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        elementType: TypeID
    ) -> TypeID {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }

    func registerSyntheticExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        includeMessageOverload: Bool,
        throwableSymbol: SymbolID? = nil
    ) {
        registerSyntheticExceptionConstructor(
            ownerSymbol: ownerSymbol,
            ownerType: ownerType,
            parameters: [],
            externalLinkName: "kk_throwable_new",
            symbols: symbols,
            interner: interner
        )
        if includeMessageOverload {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType)],
                externalLinkName: "kk_throwable_new",
                symbols: symbols,
                interner: interner
            )
        }
        // (message: String, cause: Throwable?) overload
        if includeMessageOverload, let throwableSymbol {
            let nullableThrowableType = types.make(.classType(ClassType(
                classSymbol: throwableSymbol, args: [], nullability: .nullable
            )))
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: [("message", types.stringType), ("cause", nullableThrowableType)],
                externalLinkName: "kk_throwable_new_with_cause",
                symbols: symbols,
                interner: interner
            )
        }
    }

    func registerSyntheticExceptionConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerSyntheticNullableExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        throwableSymbol: SymbolID,
        externalLinkPrefix: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableStringType = types.makeNullable(types.stringType)
        let nullableThrowableType = types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))
        let overloads: [(parameters: [(name: String, type: TypeID)], link: String)] = [
            ([], "\(externalLinkPrefix)_new"),
            ([("message", nullableStringType)], "\(externalLinkPrefix)_new_message"),
            (
                [("message", nullableStringType), ("cause", nullableThrowableType)],
                "\(externalLinkPrefix)_new_message_cause"
            ),
            ([("cause", nullableThrowableType)], "\(externalLinkPrefix)_new_cause"),
        ]
        for overload in overloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: overload.parameters,
                externalLinkName: overload.link,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticArrayIndexOutOfBoundsExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableStringType = types.makeNullable(types.stringType)
        let overloads: [(parameters: [(name: String, type: TypeID)], link: String)] = [
            ([], "kk_array_index_out_of_bounds_exception_new"),
            ([("message", nullableStringType)], "kk_array_index_out_of_bounds_exception_new_message"),
        ]
        for overload in overloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: overload.parameters,
                externalLinkName: overload.link,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticNegativeArraySizeExceptionConstructors(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nullableStringType = types.makeNullable(types.stringType)
        let overloads: [(parameters: [(name: String, type: TypeID)], link: String)] = [
            ([], "kk_negative_array_size_exception_new"),
            ([("message", nullableStringType)], "kk_negative_array_size_exception_new_message"),
        ]
        for overload in overloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: overload.parameters,
                externalLinkName: overload.link,
                symbols: symbols,
                interner: interner
            )
        }
    }
}
