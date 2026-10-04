import Foundation

struct ConstantCollector {
    func collectPropertyConstantInitializers(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceByFileID: [Int32: String]
    ) -> [SymbolID: KIRExprKind] {
        var mapping: [SymbolID: KIRExprKind] = [:]
        for file in ast.sortedFiles {
            let source = sourceByFileID[file.fileID.rawValue] ?? ""
            let inlineGetters = InlineGetterBodyIndex(source: source)
            for declID in file.topLevelDecls {
                collectPropertyConstant(declID, ast: ast, sema: sema, interner: interner, inlineGetters: inlineGetters, mapping: &mapping)
            }
        }
        return mapping
    }

    private func collectPropertyConstant(
        _ declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        inlineGetters: InlineGetterBodyIndex,
        mapping: inout [SymbolID: KIRExprKind]
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case let .propertyDecl(property):
            guard let symbol = sema.bindings.declSymbols[declID] else { return }
            // Mutable (var) properties must never be constant-folded because
            // their value can change at runtime via assignment.
            if property.isVar { return }
            // Prioritize const val values stored during sema (compile-time constants)
            if let constKind = sema.symbols.constValueExprKind(for: symbol) {
                mapping[symbol] = constKind
                if let propertySymbol = sema.symbols.symbol(symbol) {
                    let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                    for relatedID in related {
                        guard let relatedSymbol = sema.symbols.symbol(relatedID) else {
                            continue
                        }
                        if relatedSymbol.kind == .property || relatedSymbol.kind == .field {
                            mapping[relatedID] = constKind
                        }
                    }
                }
                return
            }
            let constant =
                literalConstantExpr(property: property, ast: ast, interner: interner) ??
                inlineGetterConstantExpr(
                    propertyName: interner.resolve(property.name),
                    inlineGetters: inlineGetters,
                    interner: interner
                )
            guard let constant else { return }
            mapping[symbol] = constant
            if let propertySymbol = sema.symbols.symbol(symbol) {
                let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                for relatedID in related {
                    guard let relatedSymbol = sema.symbols.symbol(relatedID) else {
                        continue
                    }
                    if relatedSymbol.kind == .property || relatedSymbol.kind == .field {
                        mapping[relatedID] = constant
                    }
                }
            }
        case let .classDecl(classDecl):
            for memberDeclID in classDecl.memberProperties {
                collectPropertyConstant(memberDeclID, ast: ast, sema: sema, interner: interner, inlineGetters: inlineGetters, mapping: &mapping)
            }
            for nestedDeclID in classDecl.nestedClasses + classDecl.nestedObjects {
                collectPropertyConstant(nestedDeclID, ast: ast, sema: sema, interner: interner, inlineGetters: inlineGetters, mapping: &mapping)
            }
        case let .objectDecl(objectDecl):
            for memberDeclID in objectDecl.memberProperties {
                collectPropertyConstant(memberDeclID, ast: ast, sema: sema, interner: interner, inlineGetters: inlineGetters, mapping: &mapping)
            }
            for nestedDeclID in objectDecl.nestedClasses + objectDecl.nestedObjects {
                collectPropertyConstant(nestedDeclID, ast: ast, sema: sema, interner: interner, inlineGetters: inlineGetters, mapping: &mapping)
            }
        default:
            break
        }
    }

    func inlineGetterConstantExpr(
        propertyName: String,
        source: String,
        interner: StringInterner
    ) -> KIRExprKind? {
        inlineGetterConstantExpr(
            propertyName: propertyName,
            inlineGetters: InlineGetterBodyIndex(source: source),
            interner: interner
        )
    }

    private func inlineGetterConstantExpr(
        propertyName: String,
        inlineGetters: InlineGetterBodyIndex,
        interner: StringInterner
    ) -> KIRExprKind? {
        guard !propertyName.isEmpty,
              let rawBody = inlineGetters.body(forPropertyName: propertyName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        if rawBody == "true" {
            return .boolLiteral(true)
        }
        if rawBody == "false" {
            return .boolLiteral(false)
        }
        let normalized = rawBody.replacingOccurrences(of: "_", with: "")
        if let intValue = Int64(normalized) {
            return .intLiteral(intValue)
        }
        if rawBody.hasPrefix("\""), rawBody.hasSuffix("\""), rawBody.count >= 2 {
            let start = rawBody.index(after: rawBody.startIndex)
            let end = rawBody.index(before: rawBody.endIndex)
            return .stringLiteral(interner.intern(String(rawBody[start ..< end])))
        }
        return nil
    }

    func literalConstantExpr(property: PropertyDecl, ast: ASTModule, interner: StringInterner) -> KIRExprKind? {
        if let initializer = property.initializer,
           let literal = literalConstantExpr(initializer, ast: ast, interner: interner)
        {
            return literal
        }
        if let getter = property.getter {
            return literalConstantExpr(getterBody: getter.body, ast: ast, interner: interner)
        }
        return nil
    }

    func literalConstantExpr(getterBody: FunctionBody, ast: ASTModule, interner: StringInterner) -> KIRExprKind? {
        switch getterBody {
        case let .expr(exprID, _):
            return literalConstantExpr(exprID, ast: ast, interner: interner)
        case let .block(exprIDs, _):
            guard let lastExprID = exprIDs.last,
                  let lastExpr = ast.arena.expr(lastExprID)
            else {
                return nil
            }
            if case let .returnExpr(valueExprID, _, _) = lastExpr,
               let valueExprID
            {
                return literalConstantExpr(valueExprID, ast: ast, interner: interner)
            }
            return literalConstantExpr(lastExprID, ast: ast, interner: interner)
        case .unit:
            return nil
        }
    }

    func literalConstantExpr(_ exprID: ExprID, ast: ASTModule, interner: StringInterner? = nil) -> KIRExprKind? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case let .intLiteral(value, _):
            return .intLiteral(value)
        case let .longLiteral(value, _):
            return .longLiteral(value)
        case let .uintLiteral(value, _):
            return .uintLiteral(value)
        case let .ulongLiteral(value, _):
            return .ulongLiteral(value)
        case let .floatLiteral(value, _):
            return .floatLiteral(value)
        case let .doubleLiteral(value, _):
            return .doubleLiteral(value)
        case let .charLiteral(value, _):
            return .charLiteral(value)
        case let .boolLiteral(value, _):
            return .boolLiteral(value)
        case let .stringLiteral(value, _):
            return .stringLiteral(value)
        case let .unaryExpr(op, operand, _):
            return literalConstantUnaryExpr(op: op, operand: operand, ast: ast, interner: interner)
        case let .binary(op, lhs, rhs, _):
            return literalConstantBinaryExpr(op: op, lhs: lhs, rhs: rhs, ast: ast, interner: interner)
        case let .memberCall(receiver, callee, _, args, _):
            guard let interner else { return nil }
            return literalConstantMemberCall(receiver: receiver, callee: callee, args: args, ast: ast, interner: interner)
        case let .stringTemplate(parts, _):
            return literalConstantStringTemplate(parts, ast: ast)
        default:
            return nil
        }
    }

    /// Handle binary expressions on literal operands: `1024 * 1024`,
    /// `Long.MIN_VALUE / 10L` (via a resolved literal), `"a" + "b"`.
    private func literalConstantBinaryExpr(
        op: BinaryOp, lhs: ExprID, rhs: ExprID, ast: ASTModule, interner: StringInterner?
    ) -> KIRExprKind? {
        guard let lhsConst = literalConstantExpr(lhs, ast: ast, interner: interner),
              let rhsConst = literalConstantExpr(rhs, ast: ast, interner: interner)
        else {
            return nil
        }
        if op == .add, case let .stringLiteral(lhsStr) = lhsConst, case let .stringLiteral(rhsStr) = rhsConst {
            guard let interner else { return nil }
            return .stringLiteral(interner.intern(interner.resolve(lhsStr) + interner.resolve(rhsStr)))
        }
        switch (lhsConst, rhsConst) {
        case let (.intLiteral(l), .intLiteral(r)):
            return integerBinaryOp(op, l, r).map { .intLiteral($0) }
        case let (.longLiteral(l), .longLiteral(r)):
            return integerBinaryOp(op, l, r).map { .longLiteral($0) }
        case let (.intLiteral(l), .longLiteral(r)):
            return integerBinaryOp(op, l, r).map { .longLiteral($0) }
        case let (.longLiteral(l), .intLiteral(r)):
            return integerBinaryOp(op, l, r).map { .longLiteral($0) }
        default:
            return nil
        }
    }

    private func integerBinaryOp(_ op: BinaryOp, _ lhs: Int64, _ rhs: Int64) -> Int64? {
        switch op {
        case .add: lhs &+ rhs
        case .subtract: lhs &- rhs
        case .multiply: lhs &* rhs
        case .divide: rhs == 0 ? nil : (lhs == Int64.min && rhs == -1 ? lhs : lhs / rhs)
        case .modulo: rhs == 0 ? nil : (lhs == Int64.min && rhs == -1 ? 0 : lhs % rhs)
        case .bitwiseAnd: lhs & rhs
        case .bitwiseOr: lhs | rhs
        case .bitwiseXor: lhs ^ rhs
        case .shl: lhs << (rhs & 63)
        case .shr: lhs >> (rhs & 63)
        case .ushr: Int64(bitPattern: UInt64(bitPattern: lhs) >> (UInt64(rhs) & 63))
        default: nil
        }
    }

    /// Handle the handful of no-argument member calls that appear in
    /// constant-like initializers translated from JVM stdlib sources:
    /// `'\r'.code`, `<int>.toByte()`, `<int>.toInt()`, `<int>.toLong()`.
    /// `.code` is parsed as a property read elsewhere; it only reaches here
    /// when written as a zero-arg call in some source shapes, so both are
    /// covered by the same `calleeName` dispatch.
    private func literalConstantMemberCall(
        receiver: ExprID, callee: InternedString, args: [CallArgument], ast: ASTModule, interner: StringInterner
    ) -> KIRExprKind? {
        guard args.isEmpty, let receiverConst = literalConstantExpr(receiver, ast: ast, interner: interner) else {
            return nil
        }
        let name = interner.resolve(callee)
        switch name {
        case "code":
            if case let .charLiteral(scalar) = receiverConst {
                return .intLiteral(Int64(scalar))
            }
            return nil
        case "toByte", "toShort", "toInt":
            guard let value = integerValue(of: receiverConst) else { return nil }
            return .intLiteral(truncatedInteger(value, name: name))
        case "toLong":
            guard let value = integerValue(of: receiverConst) else { return nil }
            return .longLiteral(value)
        default:
            return nil
        }
    }

    private func integerValue(of constant: KIRExprKind) -> Int64? {
        switch constant {
        case let .intLiteral(v): v
        case let .longLiteral(v): v
        case let .charLiteral(v): Int64(v)
        default: nil
        }
    }

    private func truncatedInteger(_ value: Int64, name: String) -> Int64 {
        switch name {
        case "toByte": Int64(Int8(truncatingIfNeeded: value))
        case "toShort": Int64(Int16(truncatingIfNeeded: value))
        default: Int64(Int32(truncatingIfNeeded: value))
        }
    }

    /// A string template with no interpolated parts (e.g. produced by macro
    /// expansion of a plain string literal) folds to its literal text.
    private func literalConstantStringTemplate(_ parts: [StringTemplatePart], ast: ASTModule) -> KIRExprKind? {
        guard parts.count == 1, case let .literal(text) = parts[0] else {
            return nil
        }
        return .stringLiteral(text)
    }

    /// Handle unary prefix expressions applied to literal operands, e.g. `-100` or `+42`.
    private func literalConstantUnaryExpr(
        op: UnaryOp, operand: ExprID, ast: ASTModule, interner: StringInterner?
    ) -> KIRExprKind? {
        guard let inner = literalConstantExpr(operand, ast: ast, interner: interner) else { return nil }
        switch op {
        case .unaryMinus: return negatedConstant(inner)
        case .unaryPlus: return positiveConstant(inner)
        case .not:
            if case let .boolLiteral(v) = inner { return .boolLiteral(!v) }
            return nil
        }
    }

    private func negatedConstant(_ inner: KIRExprKind) -> KIRExprKind? {
        switch inner {
        // Kotlin integer negation wraps at the type's minimum value.
        case let .intLiteral(v): .intLiteral(0 &- v)
        case let .longLiteral(v): .longLiteral(0 &- v)
        case let .floatLiteral(v): .floatLiteral(-v)
        case let .doubleLiteral(v): .doubleLiteral(-v)
        default: nil
        }
    }

    private func positiveConstant(_ inner: KIRExprKind) -> KIRExprKind? {
        switch inner {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral:
            inner
        default: nil
        }
    }

    /// Index of `val|var NAME ... get() = BODY` declarations in one source file.
    /// The regex pass is deferred to the first lookup so files that never reach
    /// the inline-getter fallback don't pay for the scan; the first match per
    /// name wins, matching the previous per-name `firstMatch` behavior.
    private final class InlineGetterBodyIndex {
        private static let bodyRegex = try! NSRegularExpression(
            pattern: #"(?m)^\s*(?:val|var)\s+([\p{L}_][\p{L}\p{N}_]*)[^\n]*\n\s*get\s*\(\s*\)\s*=\s*([^\n;]+)"#
        )

        private let source: String
        private var bodiesByName: [String: String]?

        init(source: String) {
            self.source = source
        }

        func body(forPropertyName name: String) -> String? {
            if bodiesByName == nil {
                bodiesByName = Self.scanBodies(in: source)
            }
            return bodiesByName?[name]
        }

        private static func scanBodies(in source: String) -> [String: String] {
            let matches = bodyRegex.matches(
                in: source,
                range: NSRange(source.startIndex ..< source.endIndex, in: source)
            )
            var bodies: [String: String] = [:]
            bodies.reserveCapacity(matches.count)
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let nameRange = Range(match.range(at: 1), in: source),
                      let bodyRange = Range(match.range(at: 2), in: source)
                else {
                    continue
                }
                let name = String(source[nameRange])
                if bodies[name] == nil {
                    bodies[name] = String(source[bodyRange])
                }
            }
            return bodies
        }
    }
}
