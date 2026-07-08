
/// KSP-476: kotlin.uuid.Uuid (class, companion, all instance/companion members,
/// ByteArray extensions, SIZE_BITS/SIZE_BYTES/LEXICAL_ORDER/NIL) is fully
/// declared in bundled Kotlin source (Stdlib/kotlin/uuid/Uuid.kt). This file
/// only registers java.util.UUID: an empty placeholder class used solely as
/// the receiver type for the `toKotlinUuid()` extension. It has no Kotlin
/// source of its own since it represents a JVM/Java platform type, not
/// kotlin.uuid.
extension DataFlowSemaPhase {
    func registerSyntheticUuidStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        _ = registerJavaUuidType(symbols: symbols, types: types, interner: interner)
    }

    private func registerJavaUuidType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let javaUtilPkg = ensurePackage(path: ["java", "util"], symbols: symbols, interner: interner)
        let javaUuidSymbol = ensureClassSymbol(
            named: "UUID",
            in: javaUtilPkg,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol = symbols.lookup(fqName: javaUtilPkg) {
            symbols.setParentSymbol(pkgSymbol, for: javaUuidSymbol)
        }
        return types.make(.classType(ClassType(
            classSymbol: javaUuidSymbol,
            args: [],
            nullability: .nonNull
        )))
    }
}
