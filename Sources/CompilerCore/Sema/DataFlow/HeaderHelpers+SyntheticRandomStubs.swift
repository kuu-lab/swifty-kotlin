
/// Synthetic stdlib compat stubs for kotlin.random.Random (KSP-466).
///
/// The core Random API (nextInt/nextLong/nextFloat/nextDouble/nextBoolean/nextBits/
/// nextBytes, the Default companion, and the Random(seed) factories) now lives in
/// real Kotlin source (Sources/CompilerCore/Stdlib/kotlin/random/{Random,XorWowRandom,
/// URandom}.kt). This file only registers the surface that is *not yet* migrated:
///
/// - `Random` itself is registered here only as a bare `.class`-kind placeholder
///   symbol (matching the `Uuid` pattern in HeaderHelpers+SyntheticUuidStubs.swift):
///   the bundled Kotlin source's `abstract class Random` declaration reuses this
///   same symbol (matching kind avoids "duplicate declaration") once header
///   collection processes it, and this placeholder just needs to exist early
///   enough for the "Collections" bucket's `List.shuffled(random: Random)`
///   registration (which runs in the same pre-bundled pass) to resolve the type.
/// - Likewise, `java.util.Random` is registered here as a bare placeholder for
///   the same reason: `kotlin.random.asKotlinRandom()`'s receiver type is
///   `java.util.Random`, and that file (JavaRandomInterop.kt) sorts before
///   JavaUtilRandom.kt in bundled-source dictionary order, so without an early
///   placeholder the receiver type would not resolve yet when that file's
///   header is collected.
/// - `nextInt(IntRange)` / `nextLong(LongRange)` range-object variants (KSP-457)
/// - `nextUInt(UIntRange)` / `nextULong(ULongRange)` range-object variants (KSP-457)
///
/// `asKotlinRandom` / `asJavaRandom` / `java.util.Random`'s own members are NOT
/// registered here: they are real Kotlin source (Sources/CompilerCore/Stdlib/
/// kotlin/random/JavaUtilRandom.kt, JavaRandomInterop.kt) — see that file's
/// header comment for why a native pointer-passthrough shim is no longer safe
/// now that kotlin.random.Random is a genuine compiled object instead of a
/// SeededRandomBox.
extension DataFlowSemaPhase {
    func registerSyntheticRandomStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinRandomPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("random")],
            symbols: symbols
        )

        // Bare placeholder: kind must match the real `abstract class Random`
        // declared in bundled Kotlin source so header collection can enrich this
        // same symbol with real members instead of erroring on redeclaration.
        let randomSymbol = ensureClassSymbol(
            named: "Random",
            in: kotlinRandomPkg,
            symbols: symbols,
            interner: interner
        )

        let randomType = types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Bare placeholder for java.util.Random; see the file header comment above.
        let javaUtilPkg = ensurePackage(
            path: ["java", "util"],
            symbols: symbols,
            interner: interner
        )
        _ = ensureClassSymbol(
            named: "Random",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )

        let intType = types.intType
        let longType = types.longType
        let ulongType = types.ulongType
        let uintType = types.uintType
        let ulongRangeType = makeRangeType(
            named: "ULongRange",
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextULong",
            externalLinkName: "kk_random_nextULong_ulongRange",
            returnType: ulongType,
            parameters: [(name: "range", type: ulongRangeType)],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextUInt",
            externalLinkName: "kk_random_nextUInt_uintRange",
            returnType: uintType,
            parameters: [(
                name: "range",
                type: makeRangeType(named: "UIntRange", symbols: symbols, types: types, interner: interner)
            )],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        // nextInt(IntRange) and nextLong(LongRange): kept as native bridges (KSP-457
        // scope). Registered as MEMBERS (not package-level extensions): now that
        // Random.kt provides real member overloads for nextInt/nextLong, this
        // compiler's overload resolution stops considering package-level
        // extensions of the same name at all (confirmed: member candidates
        // short-circuit the extension-scope fallback once any exist), so a
        // same-named package-level extension here would be unreachable from user
        // code even though the symbol itself is registered.
        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextInt",
            externalLinkName: "kk_random_nextInt_rangeObject",
            returnType: intType,
            parameters: [(
                name: "range",
                type: makeRangeType(named: "IntRange", symbols: symbols, types: types, interner: interner)
            )],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticRandomMember(
            ownerSymbol: randomSymbol,
            ownerType: randomType,
            name: "nextLong",
            externalLinkName: "kk_random_nextLong_rangeObject",
            returnType: longType,
            parameters: [(
                name: "range",
                type: makeRangeType(named: "LongRange", symbols: symbols, types: types, interner: interner)
            )],
            canThrow: true,
            symbols: symbols,
            interner: interner
        )


    }



    private func registerSyntheticRandomMember(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        name: String,
        externalLinkName: String,
        returnType: TypeID,
        parameters: [(name: String, type: TypeID)],
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let memberName = interner.intern(name)
        let memberFQName = ownerInfo.fqName + [memberName]
        guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type) &&
                existingSignature.returnType == returnType
        }) == nil else {
            return
        }
        var flags: SymbolFlags = [.synthetic]
        if canThrow {
            flags.insert(.throwingFunction)
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: memberName,
            fqName: memberFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: memberFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(memberSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                canThrow: canThrow,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: memberSymbol
        )
    }

    private func makeRangeType(
        named name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let rangesPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("ranges")],
            symbols: symbols
        )
        let symbol = ensureClassSymbol(
            named: name,
            in: rangesPkg,
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

}
