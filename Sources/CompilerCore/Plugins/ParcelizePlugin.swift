/// kotlinc `kotlin-parcelize` equivalent. Classes annotated with `@Parcelize`
/// (`kotlinx.parcelize.Parcelize` or `kotlin.android.parcel.Parcelize`) gain
/// synthetic implementations of Android's `Parcelable` interface members:
///   - `describeContents(): Int` (returning 0)
///   - `writeToParcel(dest: Parcel, flags: Int): Unit`
///
/// Configuration:
///   -P plugin:org.jetbrains.kotlin.parcelize:additionalAnnotation=<fqName>  (repeatable)
///
/// Validation rules matching kotlinc:
///   - Target must be a regular class or data class. Annotating interfaces, objects,
///     enums or annotation classes emits `KSWIFTK-SEMA-0485` ('@Parcelize' is only supported for classes).
///   - Inner classes are not supported and emit `KSWIFTK-SEMA-0486` ('@Parcelize' is not supported for inner classes).
///   - Class must implement `android.os.Parcelable` (directly or transitively); otherwise emits
///     `KSWIFTK-SEMA-0484` ('@Parcelize' class must implement 'android.os.Parcelable').
struct ParcelizePlugin: CompilerPlugin {
    let id = "org.jetbrains.kotlin.parcelize"

    private let defaultTriggers: Set<String> = [
        "kotlinx.parcelize.Parcelize",
        "kotlin.android.parcel.Parcelize",
    ]

    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext) {
        var triggers = defaultTriggers
        let additional = context.pluginConfig.optionValues(for: id, key: "additionalAnnotation")
        for ann in additional {
            triggers.insert(ann)
        }

        let symbols = context.symbols
        let interner = context.interner

        for symbol in symbols.allSymbols() {
            guard !symbol.flags.contains(.importedLibrary),
                  !symbol.flags.contains(.synthetic),
                  !symbol.flags.contains(.precomputedStdlibSynthetic),
                  hasTriggerAnnotation(symbol.id, triggers: triggers, symbols: symbols)
            else { continue }

            // 1. Kind check: must be a class
            if symbol.kind != .class {
                context.diagnostics.error(
                    "KSWIFTK-SEMA-0485",
                    "'@Parcelize' is only supported for classes.",
                    range: symbol.declSite
                )
                continue
            }

            // 2. Inner class check
            if symbol.flags.contains(.innerClass) {
                context.diagnostics.error(
                    "KSWIFTK-SEMA-0486",
                    "'@Parcelize' is not supported for inner classes.",
                    range: symbol.declSite
                )
                continue
            }

            // 3. Supertype check: must implement android.os.Parcelable
            if !implementsParcelable(symbol.id, symbols: symbols, interner: interner) {
                context.diagnostics.error(
                    "KSWIFTK-SEMA-0484",
                    "'@Parcelize' class must implement 'android.os.Parcelable'.",
                    range: symbol.declSite
                )
                continue
            }

            // 4. Synthesize Parcelable members
            generateParcelableMembers(
                for: symbol,
                context: context
            )
        }
    }

    private func hasTriggerAnnotation(
        _ symbolID: SymbolID,
        triggers: Set<String>,
        symbols: SymbolTable
    ) -> Bool {
        symbols.annotations(for: symbolID).contains { triggers.contains($0.annotationFQName) }
    }

    private func implementsParcelable(
        _ classID: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Bool {
        var visited: Set<SymbolID> = []
        var queue: [SymbolID] = [classID]
        let parcelableSimpleName = interner.intern("Parcelable")
        let androidOsParcelable: [InternedString] = [
            interner.intern("android"),
            interner.intern("os"),
            interner.intern("Parcelable"),
        ]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            if current != classID, let sym = symbols.symbol(current) {
                if sym.fqName == androidOsParcelable || sym.name == parcelableSimpleName {
                    return true
                }
            }
            for supertype in symbols.directSupertypes(for: current) {
                queue.append(supertype)
            }
        }
        return false
    }

    private func generateParcelableMembers(
        for classSymbol: SemanticSymbol,
        context: CompilerPluginSemaContext
    ) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let classID = classSymbol.id

        let ownTypeParams = types.nominalTypeParameterSymbols(for: classID)
        let enclosingTypeParams = types.enclosingTypeParameterSymbols(for: classID)
        let typeParamSymbols = enclosingTypeParams + ownTypeParams
        let selfArgs: (own: [TypeArg], enclosing: [TypeArg]) = (
            own: ownTypeParams.map {
                .invariant(types.make(.typeParam(TypeParamType(symbol: $0))))
            },
            enclosing: enclosingTypeParams.map {
                .invariant(types.make(.typeParam(TypeParamType(symbol: $0))))
            }
        )
        let classType = types.make(.classType(ClassType(
            classSymbol: classID,
            args: selfArgs.own,
            enclosingTypeArgs: selfArgs.enclosing,
            nullability: .nonNull
        )))

        // 1. Synthesize describeContents(): Int (if not already declared)
        let describeContentsName = interner.intern("describeContents")
        var describeContentsSymbol: SymbolID? = nil
        let existingDescribeContents = symbols.lookupAll(
            fqName: classSymbol.fqName + [describeContentsName]
        ).filter {
            symbols.symbol($0)?.kind == .function
                && symbols.parentSymbol(for: $0) == classID
                && symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        }
        if existingDescribeContents.isEmpty {
            let descSym = symbols.define(
                kind: .function,
                name: describeContentsName,
                fqName: classSymbol.fqName + [describeContentsName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classID, for: descSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: classType,
                    parameterTypes: [],
                    returnType: types.intType,
                    valueParameterSymbols: [],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: descSym
            )
            describeContentsSymbol = descSym
        }

        // 2. Synthesize writeToParcel(dest: Parcel, flags: Int): Unit (if not already declared)
        let writeToParcelName = interner.intern("writeToParcel")
        var writeToParcelSymbol: SymbolID? = nil
        let existingWriteToParcel = symbols.lookupAll(
            fqName: classSymbol.fqName + [writeToParcelName]
        ).filter {
            symbols.symbol($0)?.kind == .function
                && symbols.parentSymbol(for: $0) == classID
                && symbols.functionSignature(for: $0)?.parameterTypes.count == 2
        }
        if existingWriteToParcel.isEmpty {
            let writeSym = symbols.define(
                kind: .function,
                name: writeToParcelName,
                fqName: classSymbol.fqName + [writeToParcelName],
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classID, for: writeSym)

            let (parcelType, _) = resolveParcelTypeAndSymbol(symbols: symbols, types: types, interner: interner)
            let destName = interner.intern("dest")
            let flagsName = interner.intern("flags")

            let destParam = symbols.define(
                kind: .valueParameter,
                name: destName,
                fqName: classSymbol.fqName + [writeToParcelName, destName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(writeSym, for: destParam)

            let flagsParam = symbols.define(
                kind: .valueParameter,
                name: flagsName,
                fqName: classSymbol.fqName + [writeToParcelName, flagsName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(writeSym, for: flagsParam)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: classType,
                    parameterTypes: [parcelType, types.intType],
                    returnType: types.unitType,
                    valueParameterSymbols: [destParam, flagsParam],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: writeSym
            )
            writeToParcelSymbol = writeSym
        }

        // 3. Collect serializable properties (skipping @IgnoredOnParcel)
        let ignoredAnnotations: Set<String> = [
            "kotlinx.parcelize.IgnoredOnParcel",
            "kotlin.android.parcel.IgnoredOnParcel",
        ]
        let parcelProperties = symbols.declaredChildren(of: classID).filter { childID in
            guard let child = symbols.symbol(childID),
                  child.kind == .property,
                  !child.flags.contains(.synthetic),
                  !child.flags.contains(.static)
            else { return false }
            let anns = symbols.annotations(for: childID)
            return !anns.contains { ignoredAnnotations.contains($0.annotationFQName) }
        }

        // 4. Synthesize CREATOR object (`createFromParcel(parcel: Parcel): T`, `newArray(size: Int): Array<T?>`)
        let (_, resolvedParcelSymbol) = resolveParcelTypeAndSymbol(symbols: symbols, types: types, interner: interner)
        let (parcelTypeForCreator, _) = resolveParcelTypeAndSymbol(symbols: symbols, types: types, interner: interner)
        let creatorName = interner.intern("CREATOR")
        let creatorFQ = classSymbol.fqName + [creatorName]
        var creatorSymbol: SymbolID? = symbols.lookupAll(fqName: creatorFQ).first {
            symbols.parentSymbol(for: $0) == classID
                && (symbols.symbol($0)?.kind == .object || symbols.symbol($0)?.kind == .property)
        }
        var createFromParcelSymbol: SymbolID? = nil
        var newArraySymbol: SymbolID? = nil

        if creatorSymbol == nil {
            let objSym = symbols.define(
                kind: .object,
                name: creatorName,
                fqName: creatorFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(classID, for: objSym)
            if let creatorIface = resolveParcelableCreatorSymbol(symbols: symbols, interner: interner) {
                symbols.setDirectSupertypes([creatorIface], for: objSym)
                symbols.setSupertypeTypeArgs([.invariant(classType)], for: objSym, supertype: creatorIface)
            }
            creatorSymbol = objSym

            let creatorType = types.make(.classType(ClassType(
                classSymbol: objSym,
                args: [],
                nullability: .nonNull
            )))

            // createFromParcel(parcel: Parcel): T
            let createName = interner.intern("createFromParcel")
            let createFQ = creatorFQ + [createName]
            let createSym = symbols.define(
                kind: .function,
                name: createName,
                fqName: createFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(objSym, for: createSym)
            let parcelParamName = interner.intern("parcel")
            let parcelParamSym = symbols.define(
                kind: .valueParameter,
                name: parcelParamName,
                fqName: createFQ + [parcelParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(createSym, for: parcelParamSym)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: creatorType,
                    parameterTypes: [parcelTypeForCreator],
                    returnType: classType,
                    valueParameterSymbols: [parcelParamSym],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: createSym
            )
            createFromParcelSymbol = createSym

            // newArray(size: Int): Array<T?>
            let newArrayName = interner.intern("newArray")
            let newArrayFQ = creatorFQ + [newArrayName]
            let newArraySym = symbols.define(
                kind: .function,
                name: newArrayName,
                fqName: newArrayFQ,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(objSym, for: newArraySym)
            let sizeName = interner.intern("size")
            let sizeParamSym = symbols.define(
                kind: .valueParameter,
                name: sizeName,
                fqName: newArrayFQ + [sizeName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(newArraySym, for: sizeParamSym)
            let nullableClassType = types.makeNullable(classType)
            let arrayReturnType: TypeID = if let arraySym = symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Array")]) {
                types.make(.classType(ClassType(
                    classSymbol: arraySym,
                    args: [.invariant(nullableClassType)],
                    nullability: .nonNull
                )))
            } else {
                types.anyType
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: creatorType,
                    parameterTypes: [types.intType],
                    returnType: arrayReturnType,
                    valueParameterSymbols: [sizeParamSym],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: typeParamSymbols,
                    classTypeParameterCount: typeParamSymbols.count
                ),
                for: newArraySym
            )
            newArraySymbol = newArraySym
        }

        context.sema.parcelizeClasses[classID] = ParcelizeClassInfo(
            describeContentsMethod: describeContentsSymbol,
            writeToParcelMethod: writeToParcelSymbol,
            properties: parcelProperties,
            creatorObjectSymbol: creatorSymbol,
            createFromParcelMethod: createFromParcelSymbol,
            newArrayMethod: newArraySymbol,
            parcelSymbol: resolvedParcelSymbol
        )
    }

    private func resolveParcelableCreatorSymbol(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let fq = [
            interner.intern("android"),
            interner.intern("os"),
            interner.intern("Parcelable"),
            interner.intern("Creator"),
        ]
        if let sym = symbols.lookup(fqName: fq) {
            return sym
        }
        return symbols.lookup(fqName: [interner.intern("Parcelable"), interner.intern("Creator")])
    }

    private func resolveParcelTypeAndSymbol(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (TypeID, SymbolID?) {
        let parcelFQName = [
            interner.intern("android"),
            interner.intern("os"),
            interner.intern("Parcel"),
        ]
        if let parcelSym = symbols.lookup(fqName: parcelFQName) {
            return (types.make(.classType(ClassType(
                classSymbol: parcelSym,
                args: [],
                nullability: .nonNull
            ))), parcelSym)
        }
        if let parcelSym = symbols.lookup(fqName: [interner.intern("Parcel")]) {
            return (types.make(.classType(ClassType(
                classSymbol: parcelSym,
                args: [],
                nullability: .nonNull
            ))), parcelSym)
        }
        if let parcelSym = symbols.lookupByShortName(interner.intern("Parcel")).first(where: {
            let k = symbols.symbol($0)?.kind
            return k == .interface || k == .class
        }) {
            return (types.make(.classType(ClassType(
                classSymbol: parcelSym,
                args: [],
                nullability: .nonNull
            ))), parcelSym)
        }
        return (types.anyType, nil)
    }
}
