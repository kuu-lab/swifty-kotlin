/// Residual compiler/runtime anchors for kotlin.time experimental time APIs
/// (STDLIB-TIME-180).
///
/// The public operations are implemented in bundled Kotlin source. This file
/// retains only the opt-in marker, nominal/bootstrap anchors, and hidden
/// bridge declarations needed by compiler/runtime dispatch. It registers:
/// - `@ExperimentalTime`
/// - `TimeSource` with nested `WithComparableMarks`, `Monotonic`, `markNow()`, and `asClock()`
/// - `TimeMark` / `ComparableTimeMark` nominal types (their operations are Kotlin source,
///   see `Stdlib/kotlin/time/TimeMark.kt`)
/// - `AbstractDoubleTimeSource` / `AbstractLongTimeSource` / `TestTimeSource` nominal anchors
extension DataFlowSemaPhase {
    func registerSyntheticExperimentalTimeStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty
    ) {
        let kotlinTimePkg = ensurePackage(
            path: ["kotlin", "time"],
            symbols: symbols,
            interner: interner
        )

        let experimentalTimeSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalTime",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        ensureExperimentalTimeRequiresOptInMarker(
            experimentalTimeSymbol,
            symbols: symbols
        )

        let instantSymbol = ensureClassSymbol(
            named: "Instant",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let instantType = types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let clockSymbol = ensureInterfaceSymbol(
            named: "Clock",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let clockType = types.make(.classType(ClassType(
            classSymbol: clockSymbol,
            args: [],
            nullability: .nonNull
        )))
        let timeMarkSymbol = ensureInterfaceSymbol(
            named: "TimeMark",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let timeMarkType = types.make(.classType(ClassType(
            classSymbol: timeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))

        let comparableTimeMarkSymbol = ensureInterfaceSymbol(
            named: "ComparableTimeMark",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let comparableTimeMarkType = types.make(.classType(ClassType(
            classSymbol: comparableTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setDirectSupertypes([timeMarkSymbol], for: comparableTimeMarkSymbol)
        types.setNominalDirectSupertypes([timeMarkSymbol], for: comparableTimeMarkSymbol)

        // KSP-648: TimeMark / ComparableTimeMark members (elapsedNow, hasPassedNow,
        // hasNotPassedNow, plus/minus Duration, mark-to-mark minus, compareTo) are Kotlin
        // extensions in Stdlib/kotlin/time/TimeMark.kt. Only the nominal types stay
        // synthetic so that markNow() and friends can refer to them.

        let timeSourceSymbol = ensureInterfaceSymbol(
            named: "TimeSource",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        let timeSourceType = types.make(.classType(ClassType(
            classSymbol: timeSourceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let timeSourceFQName = kotlinTimePkg + [interner.intern("TimeSource")]
        if !bundledIndex.contains(ownerFQName: timeSourceFQName, name: interner.intern("markNow"), arity: 0) {
            registerExperimentalTimeMemberFunction(
                named: "markNow",
                externalLinkName: "kk_time_source_mark_now",
                ownerSymbol: timeSourceSymbol,
                ownerType: timeSourceType,
                parameters: [],
                returnType: timeMarkType,
                symbols: symbols,
                interner: interner
            )
        }
        if !bundledIndex.contains(ownerFQName: timeSourceFQName, name: interner.intern("asClock"), arity: 1) {
            registerExperimentalTimeExtensionFunction(
                named: "asClock",
                externalLinkName: "kk_time_source_as_clock",
                packageFQName: kotlinTimePkg,
                receiverType: timeSourceType,
                parameters: [(name: "origin", type: instantType)],
                returnType: clockType,
                symbols: symbols,
                interner: interner
            )
        }

        let withComparableMarksFQName = ensureExperimentalTimeNestedInterface(
            named: "WithComparableMarks",
            ownerSymbol: timeSourceSymbol,
            ownerFQName: kotlinTimePkg + [interner.intern("TimeSource")],
            symbols: symbols,
            interner: interner
        )
        guard let withComparableMarksSymbol = symbols.lookup(fqName: withComparableMarksFQName) else {
            return
        }
        let withComparableMarksType = types.make(.classType(ClassType(
            classSymbol: withComparableMarksSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setDirectSupertypes([timeSourceSymbol], for: withComparableMarksSymbol)
        types.setNominalDirectSupertypes([timeSourceSymbol], for: withComparableMarksSymbol)
        if !bundledIndex.contains(ownerFQName: withComparableMarksFQName, name: interner.intern("markNow"), arity: 0) {
            registerExperimentalTimeMemberFunction(
                named: "markNow",
                externalLinkName: "kk_time_source_mark_now",
                ownerSymbol: withComparableMarksSymbol,
                ownerType: withComparableMarksType,
                parameters: [],
                returnType: comparableTimeMarkType,
                symbols: symbols,
                interner: interner,
                flags: [.synthetic, .abstractType, .overrideMember]
            )
        }

        let abstractDoubleTimeSourceSymbol = ensureClassSymbol(
            named: "AbstractDoubleTimeSource",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.abstractType, .synthetic], for: abstractDoubleTimeSourceSymbol)
        symbols.setDirectSupertypes([withComparableMarksSymbol], for: abstractDoubleTimeSourceSymbol)
        types.setNominalDirectSupertypes([withComparableMarksSymbol], for: abstractDoubleTimeSourceSymbol)

        let abstractLongTimeSourceSymbol = ensureClassSymbol(
            named: "AbstractLongTimeSource",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.abstractType, .synthetic], for: abstractLongTimeSourceSymbol)
        symbols.setDirectSupertypes([withComparableMarksSymbol], for: abstractLongTimeSourceSymbol)
        types.setNominalDirectSupertypes([withComparableMarksSymbol], for: abstractLongTimeSourceSymbol)

        let testTimeSourceSymbol = ensureClassSymbol(
            named: "TestTimeSource",
            in: kotlinTimePkg,
            symbols: symbols,
            interner: interner
        )
        symbols.insertFlags([.synthetic], for: testTimeSourceSymbol)
        symbols.setDirectSupertypes([abstractLongTimeSourceSymbol], for: testTimeSourceSymbol)
        types.setNominalDirectSupertypes([abstractLongTimeSourceSymbol], for: testTimeSourceSymbol)

        let monotonicFQName = ensureExperimentalTimeNestedObject(
            named: "Monotonic",
            ownerSymbol: timeSourceSymbol,
            ownerFQName: kotlinTimePkg + [interner.intern("TimeSource")],
            symbols: symbols,
            interner: interner
        )
        guard let monotonicSymbol = symbols.lookup(fqName: monotonicFQName) else {
            return
        }
        let monotonicType = types.make(.classType(ClassType(
            classSymbol: monotonicSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setDirectSupertypes([withComparableMarksSymbol], for: monotonicSymbol)
        types.setNominalDirectSupertypes([withComparableMarksSymbol], for: monotonicSymbol)
        if !bundledIndex.contains(ownerFQName: monotonicFQName, name: interner.intern("markNow"), arity: 0) {
            registerExperimentalTimeMemberFunction(
                named: "markNow",
                externalLinkName: "kk_time_source_monotonic_mark_now",
                ownerSymbol: monotonicSymbol,
                ownerType: monotonicType,
                parameters: [],
                returnType: comparableTimeMarkType,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func ensureExperimentalTimeNestedInterface(
        named interfaceName: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let interned = interner.intern(interfaceName)
        let fqName = ownerFQName + [interned]
        if let existing = symbols.lookup(fqName: fqName),
           let info = symbols.symbol(existing)
        {
            return info.fqName
        }
        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: interned,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: interfaceSymbol)
        return fqName
    }

    private func ensureExperimentalTimeRequiresOptInMarker(
        _ annotationSymbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: annotationSymbol)
        let requiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: ["level=RequiresOptIn.Level.ERROR"]
        )
        if !annotations.contains(requiresOptIn) {
            annotations.append(requiresOptIn)
        }
        // Mirrors the official `kotlin.time.ExperimentalTime` @Target list. Restricting
        // this to ANNOTATION_CLASS would reject the supported propagating opt-in form
        // (e.g. `@ExperimentalTime fun foo()`), which the opt-in diagnostic itself suggests.
        let target = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ]
        )
        if !annotations.contains(target) {
            annotations.append(target)
        }
        let retention = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: ["AnnotationRetention.BINARY"]
        )
        if !annotations.contains(retention) {
            annotations.append(retention)
        }
        symbols.setAnnotations(annotations, for: annotationSymbol)
    }

    private func ensureExperimentalTimeNestedObject(
        named objectName: String,
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        let interned = interner.intern(objectName)
        let fqName = ownerFQName + [interned]
        if let existing = symbols.lookup(fqName: fqName),
           let info = symbols.symbol(existing)
        {
            return info.fqName
        }
        let objectSymbol = symbols.define(
            kind: .object,
            name: interned,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        symbols.setParentSymbol(ownerSymbol, for: objectSymbol)
        return fqName
    }

    private func registerExperimentalTimeExtensionFunction(
        named name: String,
        externalLinkName: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let desiredParameterTypes = parameters.map { $0.type }
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType &&
                signature.parameterTypes == desiredParameterTypes &&
                signature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: desiredParameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerExperimentalTimeMemberFunction(
        named name: String,
        externalLinkName: String?,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner,
        isOperator: Bool = false,
        visibility: Visibility = .public,
        flags explicitFlags: SymbolFlags? = nil
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        let desiredParameterTypes = parameters.map { $0.type }
        if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == ownerType &&
                signature.parameterTypes == desiredParameterTypes &&
                signature.returnType == returnType
        }) {
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            if let explicitFlags {
                symbols.insertFlags(explicitFlags, for: existing)
            }
            return
        }

        var flags: SymbolFlags = explicitFlags ?? [.synthetic]
        if isOperator {
            flags.insert(.operatorFunction)
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: visibility,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        }

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: desiredParameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

}
