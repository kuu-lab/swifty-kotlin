/// Synthetic Kotlin/JS `JsArray<T>` external class registration.
///
/// Registers `kotlin.js.JsArray` as a generic open class with a single
/// invariant type parameter `T` and supertype `JsAny`. No member functions
/// are registered here; this only provides the class surface for type-checking.
extension DataFlowSemaPhase {
    func registerSyntheticJsArrayExternalClassStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )

        let className = interner.intern("JsArray")
        let classFQName = kotlinJsPkg + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName),
           symbols.symbol(existing)?.kind == .class {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .openType]
            )
        }
        if let packageSymbol = symbols.lookup(fqName: kotlinJsPkg) {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
        symbols.insertFlags([.synthetic, .openType], for: classSymbol)

        let typeParamName = interner.intern("T")
        let typeParamFQName = classFQName + [typeParamName]
        let typeParamSymbol: SymbolID
        if let existing = symbols.lookup(fqName: typeParamFQName),
           symbols.symbol(existing)?.kind == .typeParameter {
            typeParamSymbol = existing
        } else {
            typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: typeParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(classSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.nullableAnyType], for: typeParamSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: classSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: classSymbol)
        symbols.setPropertyType(classType, for: classSymbol)

        let jsAnySymbol = ensureInterfaceSymbol(
            named: "JsAny",
            in: kotlinJsPkg,
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([jsAnySymbol], for: classSymbol)
        types.setNominalDirectSupertypes([jsAnySymbol], for: classSymbol)
    }
}
