/// KUU-1357: shared helpers for KClass reflection metadata emission —
/// multi-supertype display names plus companion / nested-class registration.
///
/// The runtime splits the '|'-joined `supertypeNameRaw` slot back into one
/// `KType` per entry, so `KClass.supertypes` can return class + interface
/// supertypes instead of the previous single class-name string.
///
/// Ordering matches kotlin-reflect: declared supertypes in source order
/// (Kotlin requires the superclass first when one is listed), then an
/// implicit `kotlin.Any` for interfaces and for classes whose only
/// supertypes are interfaces.

/// Returns the '|'-joined display names of every direct supertype of a
/// nominal symbol, or nil when the type has no supertypes (kotlin.Any
/// itself) or the symbol cannot be resolved.
func kclassSupertypeDisplayNamesJoined(
    for symbolID: SymbolID,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    guard let symbol = sema.symbols.symbol(symbolID) else { return nil }
    let fqName = symbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
    if fqName == "kotlin.Any" {
        return nil
    }
    if symbol.kind == .annotationClass {
        // kotlin-reflect reports annotation classes as extending
        // kotlin.Annotation and kotlin.Any regardless of the Sema-recorded
        // implicit Any edge.
        return "kotlin.Annotation|kotlin.Any"
    }

    var entries: [(display: String, isClassKind: Bool)] = []
    for superSymbolID in sema.symbols.directSupertypes(for: symbolID) {
        guard let superSymbol = sema.symbols.symbol(superSymbolID),
              let display = kclassSupertypeDisplayName(
                  child: symbolID,
                  superSymbol: superSymbol,
                  sema: sema,
                  interner: interner
              ),
              !display.isEmpty,
              !entries.contains(where: { $0.display == display })
        else { continue }
        entries.append((display, superSymbol.kind == .class))
    }

    switch symbol.kind {
    case .enumClass:
        if !entries.contains(where: { $0.display.hasPrefix("kotlin.Enum") }) {
            let enumArg = fqName.isEmpty ? interner.resolve(symbol.name) : fqName
            entries.insert(("kotlin.Enum<\(enumArg)>", true), at: 0)
        }
    case .interface:
        if !entries.contains(where: { $0.display == "kotlin.Any" }) {
            entries.append(("kotlin.Any", true))
        }
    default:
        if entries.isEmpty {
            entries = [("kotlin.Any", true)]
        } else {
            let hasRealClassSuper = entries.contains {
                $0.isClassKind && $0.display != "kotlin.Any"
            }
            if hasRealClassSuper {
                // JVM lists kotlin.Any only when it is the direct superclass.
                entries.removeAll { $0.display == "kotlin.Any" }
            } else if !entries.contains(where: { $0.display == "kotlin.Any" }) {
                entries.append(("kotlin.Any", true))
            }
        }
    }
    return entries.map(\.display).joined(separator: "|")
}

/// Renders one direct supertype as `fq.Name<arg, …>`, using the type
/// arguments the child passes to a generic supertype when Sema tracks them.
private func kclassSupertypeDisplayName(
    child: SymbolID,
    superSymbol: SemanticSymbol,
    sema: SemaModule,
    interner: StringInterner
) -> String? {
    let superFQName = superSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
    guard !superFQName.isEmpty else { return nil }
    let args = sema.types.nominalSupertypeTypeArgs(for: child, supertype: superSymbol.id)
    guard !args.isEmpty else { return superFQName }
    let rendered = args.map { arg -> String in
        switch arg {
        case .star:
            return "*"
        case .invariant(let type), .out(let type), .in(let type):
            return sema.types.displayName(of: type, symbols: sema.symbols, interner: interner)
        }
    }
    return "\(superFQName)<\(rendered.joined(separator: ", "))>"
}

/// Emits `__kk_kclass_register_companion` (when the class declares a
/// companion object) and `__kk_kclass_register_nested_class` for every
/// non-synthetic nested nominal child, keyed by the parent class's type
/// token (KUU-1357).
func emitKClassCompanionAndNestedRegistration(
    classSymbol: SymbolID,
    typeTokenExpr: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) {
    guard let symbol = sema.symbols.symbol(classSymbol) else { return }
    let intType = sema.types.intType
    let stringType = sema.types.stringType

    func nestedTokenExpr(for nested: SymbolID) -> KIRExprID {
        let nestedType = sema.types.make(.classType(ClassType(
            classSymbol: nested, args: [], nullability: .nonNull
        )))
        let token = RuntimeTypeCheckToken.encode(type: nestedType, sema: sema, interner: interner)
        let expr = arena.appendExpr(.intLiteral(token), type: intType)
        instructions.append(.constValue(result: expr, value: .intLiteral(token)))
        return expr
    }

    func nestedNameExpr(for nested: SymbolID) -> KIRExprID {
        let nestedFQName = sema.symbols.symbol(nested)?.fqName
            .map { interner.resolve($0) }.joined(separator: ".") ?? ""
        let interned = interner.intern(nestedFQName)
        let expr = arena.appendExpr(.stringLiteral(interned), type: stringType)
        instructions.append(.constValue(result: expr, value: .stringLiteral(interned)))
        return expr
    }

    func emitRegistration(_ callee: String, nested: SymbolID) {
        let tokenExpr = nestedTokenExpr(for: nested)
        let nameExpr = nestedNameExpr(for: nested)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(callee),
            arguments: [typeTokenExpr, tokenExpr, nameExpr],
            result: arena.appendTemporary(type: intType),
            canThrow: false,
            thrownResult: nil
        ))
    }

    if let companion = sema.symbols.companionObjectSymbol(for: classSymbol) {
        emitRegistration("__kk_kclass_register_companion", nested: companion)
    }

    for child in sema.symbols.children(ofFQName: symbol.fqName) {
        guard let childSym = sema.symbols.symbol(child),
              !childSym.flags.contains(.synthetic)
        else { continue }
        switch childSym.kind {
        case .class, .interface, .object, .enumClass, .annotationClass:
            emitRegistration("__kk_kclass_register_nested_class", nested: child)
        default:
            break
        }
    }
}
