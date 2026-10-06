final class ConstPropertyEvaluator {
    private let ast: ASTModule
    private let sema: SemaModule
    private let interner: StringInterner
    private var properties: [SymbolID: PropertyDecl] = [:]
    private var collected: Set<DeclID> = []
    private var evaluating: Set<SymbolID> = []
    private var evaluated: Set<SymbolID> = []
    private var failed: Set<SymbolID> = []

    init(ast: ASTModule, sema: SemaModule, interner: StringInterner) {
        self.ast = ast
        self.sema = sema
        self.interner = interner
        for declID in ast.activeDeclarationIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            collectProperties(in: declID)
        }
    }

    private func collectProperties(in declID: DeclID) {
        guard collected.insert(declID).inserted else { return }
        switch ast.arena.decl(declID) {
        case let .propertyDecl(property):
            guard property.modifiers.contains(.const),
                  let symbol = sema.bindings.declSymbol(for: declID)
            else { return }
            properties[symbol] = property
        case let .classDecl(decl):
            for child in decl.memberProperties + decl.nestedClasses + decl.nestedObjects {
                collectProperties(in: child)
            }
            if let companion = decl.companionObject { collectProperties(in: companion) }
        case let .interfaceDecl(decl):
            for child in decl.memberProperties + decl.nestedClasses + decl.nestedObjects {
                collectProperties(in: child)
            }
            if let companion = decl.companionObject { collectProperties(in: companion) }
        case let .objectDecl(decl):
            for child in decl.memberProperties + decl.nestedClasses + decl.nestedObjects {
                collectProperties(in: child)
            }
        default:
            break
        }
    }

    func evaluate(diagnostics: DiagnosticEngine) {
        for symbol in properties.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let property = properties[symbol], property.initializer != nil else { continue }
            if constant(for: symbol) == nil {
                diagnostics.error(
                    "KSWIFTK-SEMA-0083",
                    "'const val' initializer must be a compile-time constant expression.",
                    range: property.range
                )
            }
        }
    }

    private func constant(for symbol: SymbolID) -> KIRExprKind? {
        if properties[symbol] == nil || evaluated.contains(symbol),
           let value = sema.symbols.constValueExprKind(for: symbol) { return value }
        if let value = primitiveCompanionConstant(for: symbol) { return value }
        guard !failed.contains(symbol), evaluating.count < DataFlowSemaPhase.maxStructuralRecursionDepth,
              let property = properties[symbol], !property.isVar,
              let initializer = property.initializer,
              evaluating.insert(symbol).inserted
        else { return nil }
        defer { evaluating.remove(symbol) }
        let collector = ConstantCollector(
            resolvedConstant: { [self] expr in resolvedConstant(for: expr) },
            canFoldMemberCall: { [self] expr in canFoldMemberCall(expr) }
        )
        guard let value = collector.literalConstantExpr(initializer, ast: ast, interner: interner) else {
            failed.insert(symbol)
            return nil
        }
        let type = sema.symbols.propertyType(for: symbol) ?? sema.types.nullableAnyType
        let converted = collector.convertConstant(value, to: type, types: sema.types)
        sema.symbols.setConstValueExprKind(converted, for: symbol)
        sema.bindings.bindConstExprValue(initializer, value: converted)
        evaluated.insert(symbol)
        return converted
    }

    private func resolvedConstant(for expr: ExprID) -> KIRExprKind? {
        let callee = sema.bindings.callBinding(for: expr)?.chosenCallee
        let property = callee.flatMap {
            sema.symbols.accessorOwnerProperty(for: $0) ?? sema.symbols.parentSymbol(for: $0)
        }
        if let symbol = sema.bindings.identifierSymbol(for: expr) ?? property,
           let info = sema.symbols.symbol(symbol), info.kind == .property,
           info.flags.contains(.constValue) || primitiveCompanionConstant(for: symbol) != nil
        {
            return constant(for: symbol)
        }
        if case let .intLiteral(value, _) = ast.arena.expr(expr),
           let type = sema.bindings.exprType(for: expr)
        {
            return ConstantCollector().convertConstant(.intLiteral(value), to: type, types: sema.types)
        }
        return nil
    }

    private func canFoldMemberCall(_ expr: ExprID) -> Bool {
        guard case let .memberCall(receiver, callee, _, args, _) = ast.arena.expr(expr) else { return false }
        let name = interner.resolve(callee)
        if name == "inv" {
            guard args.isEmpty, let receiverType = sema.bindings.exprType(for: receiver) else { return false }
            return receiverType == sema.types.intType || receiverType == sema.types.longType
        }
        guard ["and", "or", "xor", "shl", "shr", "ushr"].contains(name) else { return true }
        guard args.count == 1,
              let receiverType = sema.bindings.exprType(for: receiver),
              receiverType == sema.types.intType || receiverType == sema.types.longType,
              let argumentType = sema.bindings.exprType(for: args[0].expr)
        else { return false }
        return argumentType == (["shl", "shr", "ushr"].contains(name) ? sema.types.intType : receiverType)
    }

    // Kotlin's primitive companion constants remain compile-time constants
    // even when their source-backed stdlib declarations use getters.
    private func primitiveCompanionConstant(for symbol: SymbolID) -> KIRExprKind? {
        guard let info = sema.symbols.symbol(symbol), info.kind == .property,
              info.fqName == [interner.intern("kotlin"), info.name],
              let receiver = sema.symbols.extensionPropertyReceiverType(for: symbol),
              case let .classType(receiverClass) = sema.types.kind(of: receiver),
              let owner = sema.symbols.symbol(receiverClass.classSymbol)
        else { return nil }
        let path = owner.fqName.map { interner.resolve($0) }
        guard path.count == 3, path[0] == "kotlin", path[2] == "Companion" else { return nil }
        let member = interner.resolve(info.name)
        switch (path[1], member) {
        case ("Byte", "MIN_VALUE"): return .intLiteral(-128)
        case ("Byte", "MAX_VALUE"): return .intLiteral(127)
        case ("Short", "MIN_VALUE"): return .intLiteral(-32768)
        case ("Short", "MAX_VALUE"): return .intLiteral(32767)
        case ("Int", "MIN_VALUE"): return .intLiteral(Int64(Int32.min))
        case ("Int", "MAX_VALUE"): return .intLiteral(Int64(Int32.max))
        case ("Long", "MIN_VALUE"): return .longLiteral(Int64.min)
        case ("Long", "MAX_VALUE"): return .longLiteral(Int64.max)
        case ("Float", "MIN_VALUE"): return .floatLiteral(Double(Float.leastNonzeroMagnitude))
        case ("Float", "MAX_VALUE"): return .floatLiteral(Double(Float.greatestFiniteMagnitude))
        case ("Float", "POSITIVE_INFINITY"): return .floatLiteral(.infinity)
        case ("Float", "NEGATIVE_INFINITY"): return .floatLiteral(-.infinity)
        case ("Float", "NaN"): return .floatLiteral(Double(Float(bitPattern: 0x7FC0_0000)))
        case ("Double", "MIN_VALUE"): return .doubleLiteral(Double.leastNonzeroMagnitude)
        case ("Double", "MAX_VALUE"): return .doubleLiteral(Double.greatestFiniteMagnitude)
        case ("Double", "POSITIVE_INFINITY"): return .doubleLiteral(.infinity)
        case ("Double", "NEGATIVE_INFINITY"): return .doubleLiteral(-.infinity)
        case ("Double", "NaN"): return .doubleLiteral(Double(bitPattern: 0x7FF8_0000_0000_0000))
        case ("Byte", "SIZE_BITS"): return .intLiteral(8)
        case ("Byte", "SIZE_BYTES"): return .intLiteral(1)
        case ("Short", "SIZE_BITS"): return .intLiteral(16)
        case ("Short", "SIZE_BYTES"): return .intLiteral(2)
        case ("Int", "SIZE_BITS"), ("Float", "SIZE_BITS"): return .intLiteral(32)
        case ("Int", "SIZE_BYTES"), ("Float", "SIZE_BYTES"): return .intLiteral(4)
        case ("Long", "SIZE_BITS"), ("Double", "SIZE_BITS"): return .intLiteral(64)
        case ("Long", "SIZE_BYTES"), ("Double", "SIZE_BYTES"): return .intLiteral(8)
        default: return nil
        }
    }
}
