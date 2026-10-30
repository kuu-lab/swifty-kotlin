import Foundation

struct ConstantCollector {
    /// kotlinc evaluates floating-point comparisons with two different rules.
    /// Its constant evaluator (`const val`, annotation arguments) uses
    /// `equals`/`compareTo`: `NaN == NaN`, `-0.0 != 0.0`, `-0.0 < 0.0`, and
    /// NaN orders above every other value. Every other expression — plain
    /// `val` initializers and the String concatenations the lowering folds —
    /// follows IEEE 754, so `-0.0 == 0.0` and `0.0 < NaN` is false.
    enum FloatingPointComparisonSemantics {
        case constantEvaluation
        case ieee754
    }

    var resolvedConstant: ((ExprID) -> KIRExprKind?)? = nil
    var canFoldMemberCall: ((ExprID) -> Bool)? = nil
    var floatingPointComparisonSemantics: FloatingPointComparisonSemantics = .constantEvaluation

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
            if let constKind = sema.symbols.constValueExprKind(for: symbol) {
                mapping[symbol] = constKind
                if let propertySymbol = sema.symbols.symbol(symbol) {
                    let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                    for relatedID in related {
                        guard let relatedSymbol = sema.symbols.symbol(relatedID),
                              !areDistinctFilePrivateProperties(propertySymbol, relatedSymbol, symbols: sema.symbols),
                              sema.symbols.extensionPropertyReceiverType(for: relatedID)
                                  == sema.symbols.extensionPropertyReceiverType(for: symbol)
                        else {
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
            // A read may fold to the initializer's raw scalar only when the
            // property's storage holds that same raw scalar. Reference-typed
            // vals box their value (an `Any` Double is a heap handle, not the
            // literal's bits) and nullable primitives with
            // sentinel-colliding payloads (Double?/Float?/Long?/ULong?) use
            // box-or-sentinel slots, where a raw `-0.0` or `Long.MIN_VALUE`
            // would read as null — both made `val x: Any = -0.0` compare
            // `x == -0.0`/`x == null` wrong (KUU-3784).
            if isRawScalarLiteral(constant),
               !storesRawScalar(sema.symbols.propertyType(for: symbol), sema: sema)
            {
                return
            }
            mapping[symbol] = constant
            if let propertySymbol = sema.symbols.symbol(symbol) {
                let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                for relatedID in related {
                    guard let relatedSymbol = sema.symbols.symbol(relatedID),
                          !areDistinctFilePrivateProperties(propertySymbol, relatedSymbol, symbols: sema.symbols),
                          sema.symbols.extensionPropertyReceiverType(for: relatedID)
                              == sema.symbols.extensionPropertyReceiverType(for: symbol)
                    else {
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

    private func isRawScalarLiteral(_ constant: KIRExprKind) -> Bool {
        switch constant {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral:
            return true
        default:
            return false
        }
    }

    /// Whether a property of this type stores the scalar value's raw bits —
    /// a non-null primitive always does, and a nullable primitive does for
    /// the primitives whose raw range cannot collide with the null sentinel.
    /// Every other type (Any, class types, type parameters, String, ...)
    /// stores a heap handle that a raw literal cannot represent.
    private func storesRawScalar(_ propertyType: TypeID?, sema: SemaModule) -> Bool {
        guard let propertyType,
              case let .primitive(primitive, nullability) = sema.types.kind(of: propertyType)
        else {
            return false
        }
        return nullability == .nonNull || !primitive.rawValueCollidesWithNullSentinel
    }

    private func areDistinctFilePrivateProperties(
        _ property: SemanticSymbol,
        _ related: SemanticSymbol,
        symbols: SymbolTable
    ) -> Bool {
        // Matching FQNs do not imply shared storage for file-private declarations.
        guard symbols.parentSymbol(for: property.id) == nil,
              let fileID = symbols.sourceFileID(for: property.id) ?? property.declSite?.start.file
        else { return false }
        return symbols.canCoexistAsFilePrivateTopLevelCallable(
            kind: property.kind, visibility: property.visibility, fileID: fileID, existing: related
        )
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
        if let constant = resolvedConstant?(exprID) {
            return constant
        }
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
        case .nullLiteral:
            return .null
        case let .boolLiteral(value, _):
            return .boolLiteral(value)
        case let .stringLiteral(value, _):
            return .stringLiteral(value)
        case let .unaryExpr(op, operand, _):
            return literalConstantUnaryExpr(op: op, operand: operand, ast: ast, interner: interner)
        case let .binary(op, lhs, rhs, _):
            return literalConstantBinaryExpr(op: op, lhs: lhs, rhs: rhs, ast: ast, interner: interner)
        case let .memberCall(receiver, callee, _, args, _):
            guard let interner, canFoldMemberCall?(exprID) != false else { return nil }
            return literalConstantMemberCall(
                exprID: exprID,
                receiver: receiver,
                callee: callee,
                args: args,
                ast: ast,
                interner: interner
            )
        case let .indexedAccess(receiver, indices, _):
            // `s[i]` is the String.get operator; Sema gates it to the builtin
            // kotlin.text.get through canFoldMemberCall just like `.get(i)`.
            guard let interner, canFoldMemberCall?(exprID) != false, indices.count == 1,
                  case let .stringLiteral(value) = literalConstantExpr(receiver, ast: ast, interner: interner),
                  case let .intLiteral(index) = literalConstantExpr(indices[0], ast: ast, interner: interner)
            else {
                return nil
            }
            let utf16 = Array(interner.resolve(value).utf16)
            guard index >= 0, index < Int64(utf16.count) else { return nil }
            return .charLiteral(UInt32(utf16[Int(index)]))
        case let .stringTemplate(parts, _):
            return literalConstantStringTemplate(parts)
        default:
            return nil
        }
    }

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
            return comparison(op, l, r) ?? integerBinaryOp(op, l, r, width: 32).map { .intLiteral($0) }
        case let (.longLiteral(l), .longLiteral(r)):
            return comparison(op, l, r) ?? integerBinaryOp(op, l, r).map { .longLiteral($0) }
        case let (.intLiteral(l), .longLiteral(r)):
            return comparison(op, l, r) ?? integerBinaryOp(op, l, r).map { .longLiteral($0) }
        case let (.longLiteral(l), .intLiteral(r)):
            return comparison(op, l, r) ?? integerBinaryOp(op, l, r).map { .longLiteral($0) }
        case let (.charLiteral(l), .intLiteral(r)):
            // Kotlin Char arithmetic wraps in the UTF-16 code-unit domain.
            switch op {
            case .add: return .charLiteral(UInt32(UInt16(truncatingIfNeeded: Int64(l) &+ r)))
            case .subtract: return .charLiteral(UInt32(UInt16(truncatingIfNeeded: Int64(l) &- r)))
            default: return nil
            }
        case let (.charLiteral(l), .charLiteral(r)):
            if op == .subtract { return .intLiteral(Int64(l) - Int64(r)) }
            return comparison(op, l, r)
        case let (.boolLiteral(l), .boolLiteral(r)):
            switch op {
            case .equal: return .boolLiteral(l == r)
            case .notEqual: return .boolLiteral(l != r)
            case .logicalAnd: return .boolLiteral(l && r)
            case .logicalOr: return .boolLiteral(l || r)
            default: return nil
            }
        case let (.stringLiteral(l), .stringLiteral(r)):
            switch op {
            case .equal: return .boolLiteral(l == r)
            case .notEqual: return .boolLiteral(l != r)
            default: return nil
            }
        case let (.floatLiteral(l), .floatLiteral(r)):
            let lhs = Float(l)
            let rhs = Float(r)
            return floatingPointComparison(op, lhs, rhs)
                ?? floatingPointBinaryOp(op, lhs, rhs).map { .floatLiteral(Double($0)) }
        case let (.floatLiteral(l), .doubleLiteral(r)):
            let lhs = Double(Float(l))
            return floatingPointComparison(op, lhs, r) ?? floatingPointBinaryOp(op, lhs, r).map { .doubleLiteral($0) }
        case let (.doubleLiteral(l), .floatLiteral(r)):
            let rhs = Double(Float(r))
            return floatingPointComparison(op, l, rhs) ?? floatingPointBinaryOp(op, l, rhs).map { .doubleLiteral($0) }
        case let (.doubleLiteral(l), .doubleLiteral(r)):
            return floatingPointComparison(op, l, r) ?? floatingPointBinaryOp(op, l, r).map { .doubleLiteral($0) }
        case let (.intLiteral(l), .floatLiteral(r)), let (.longLiteral(l), .floatLiteral(r)):
            let lhs = Float(l)
            let rhs = Float(r)
            return floatingPointComparison(op, lhs, rhs)
                ?? floatingPointBinaryOp(op, lhs, rhs).map { .floatLiteral(Double($0)) }
        case let (.floatLiteral(l), .intLiteral(r)), let (.floatLiteral(l), .longLiteral(r)):
            let lhs = Float(l)
            let rhs = Float(r)
            return floatingPointComparison(op, lhs, rhs)
                ?? floatingPointBinaryOp(op, lhs, rhs).map { .floatLiteral(Double($0)) }
        case let (.intLiteral(l), .doubleLiteral(r)), let (.longLiteral(l), .doubleLiteral(r)):
            let lhs = Double(l)
            return floatingPointComparison(op, lhs, r) ?? floatingPointBinaryOp(op, lhs, r).map { .doubleLiteral($0) }
        case let (.doubleLiteral(l), .intLiteral(r)), let (.doubleLiteral(l), .longLiteral(r)):
            let rhs = Double(r)
            return floatingPointComparison(op, l, rhs) ?? floatingPointBinaryOp(op, l, rhs).map { .doubleLiteral($0) }
        default:
            return nil
        }
    }

    private func floatingPointBinaryOp<T: BinaryFloatingPoint>(_ op: BinaryOp, _ lhs: T, _ rhs: T) -> T? {
        switch op {
        case .add: lhs + rhs
        case .subtract: lhs - rhs
        case .multiply: lhs * rhs
        case .divide: lhs / rhs
        case .modulo: lhs.truncatingRemainder(dividingBy: rhs)
        default: nil
        }
    }

    private func comparison<T: Comparable>(_ op: BinaryOp, _ lhs: T, _ rhs: T) -> KIRExprKind? {
        switch op {
        case .equal: .boolLiteral(lhs == rhs)
        case .notEqual: .boolLiteral(lhs != rhs)
        case .lessThan: .boolLiteral(lhs < rhs)
        case .lessOrEqual: .boolLiteral(lhs <= rhs)
        case .greaterThan: .boolLiteral(lhs > rhs)
        case .greaterOrEqual: .boolLiteral(lhs >= rhs)
        default: nil
        }
    }

    private func floatingPointComparison<T: BinaryFloatingPoint>(_ op: BinaryOp, _ lhs: T, _ rhs: T) -> KIRExprKind? {
        guard floatingPointComparisonSemantics == .constantEvaluation else {
            return comparison(op, lhs, rhs)
        }
        let order = compareFloatingPoint(lhs, rhs)
        switch op {
        case .equal: return .boolLiteral(kotlinConstantFloatingPointEquals(lhs, rhs))
        case .notEqual: return .boolLiteral(!kotlinConstantFloatingPointEquals(lhs, rhs))
        case .lessThan: return .boolLiteral(order < 0)
        case .lessOrEqual: return .boolLiteral(order <= 0)
        case .greaterThan: return .boolLiteral(order > 0)
        case .greaterOrEqual: return .boolLiteral(order >= 0)
        default: return nil
        }
    }

    private func kotlinConstantFloatingPointEquals<T: BinaryFloatingPoint>(_ lhs: T, _ rhs: T) -> Bool {
        if lhs.isNaN || rhs.isNaN { return lhs.isNaN && rhs.isNaN }
        if lhs == 0, rhs == 0 { return lhs.sign == rhs.sign }
        return lhs == rhs
    }

    private func integerBinaryOp(_ op: BinaryOp, _ lhs: Int64, _ rhs: Int64, width: Int = 64) -> Int64? {
        let shift = rhs & Int64(width - 1)
        let result: Int64? = switch op {
        case .add: lhs &+ rhs
        case .subtract: lhs &- rhs
        case .multiply: lhs &* rhs
        case .divide: rhs == 0 ? nil : (lhs == Int64.min && rhs == -1 ? lhs : lhs / rhs)
        case .modulo: rhs == 0 ? nil : (lhs == Int64.min && rhs == -1 ? 0 : lhs % rhs)
        case .bitwiseAnd: lhs & rhs
        case .bitwiseOr: lhs | rhs
        case .bitwiseXor: lhs ^ rhs
        case .shl: lhs << shift
        case .shr: lhs >> shift
        case .ushr:
            width == 32
                ? Int64(UInt32(truncatingIfNeeded: lhs) >> shift)
                : Int64(bitPattern: UInt64(bitPattern: lhs) >> shift)
        default: nil
        }
        return result.map { width == 32 ? Int64(Int32(truncatingIfNeeded: $0)) : $0 }
    }

    /// `.code` is parsed as a property read elsewhere; it only reaches here
    /// when written as a zero-arg call in some source shapes, so both are
    /// covered by the same `calleeName` dispatch.
    private func literalConstantMemberCall(
        exprID: ExprID,
        receiver: ExprID,
        callee: InternedString,
        args: [CallArgument],
        ast: ASTModule,
        interner: StringInterner
    ) -> KIRExprKind? {
        guard let receiverConst = literalConstantExpr(receiver, ast: ast, interner: interner) else {
            return nil
        }
        let name = interner.resolve(callee)
        if canFoldMemberCall?(exprID) == true,
           case let .stringLiteral(value) = receiverConst
        {
            let receiverText = interner.resolve(value)
            switch name {
            case "trimIndent" where args.isEmpty:
                return .stringLiteral(interner.intern(trimIndentString(receiverText)))
            case "trimMargin" where args.count <= 1:
                let marginPrefix: String
                if args.isEmpty {
                    marginPrefix = "|"
                } else {
                    guard !args[0].isSpread,
                          case let .stringLiteral(prefix) = literalConstantExpr(
                              args[0].expr, ast: ast, interner: interner
                          )
                    else {
                        return nil
                    }
                    marginPrefix = interner.resolve(prefix)
                }
                let prefixUnits = Array(marginPrefix.utf16)
                guard !isKotlinBlank(prefixUnits) else { return nil }
                return .stringLiteral(interner.intern(trimMarginString(receiverText, prefix: prefixUnits)))
            default:
                break
            }
        }
        if args.count == 1, canFoldMemberCall != nil,
           let argument = literalConstantExpr(args[0].expr, ast: ast, interner: interner)
        {
            if name == "compareTo" {
                return literalConstantCompareTo(receiverConst, argument, interner: interner)
            }
            if case let .boolLiteral(lhs) = receiverConst, case let .boolLiteral(rhs) = argument {
                switch name {
                case "and": return .boolLiteral(lhs && rhs)
                case "or": return .boolLiteral(lhs || rhs)
                case "xor": return .boolLiteral(lhs != rhs)
                default: break
                }
            }
            if let op = constantBitwiseOperator(name) {
                switch (receiverConst, argument) {
                case let (.intLiteral(lhs), .intLiteral(rhs)):
                    return integerBinaryOp(op, lhs, rhs, width: 32).map { .intLiteral($0) }
                case let (.longLiteral(lhs), .intLiteral(rhs)) where op == .shl || op == .shr || op == .ushr:
                    return integerBinaryOp(op, lhs, rhs).map { .longLiteral($0) }
                case let (.longLiteral(lhs), .longLiteral(rhs)) where op == .bitwiseAnd || op == .bitwiseOr || op == .bitwiseXor:
                    return integerBinaryOp(op, lhs, rhs).map { .longLiteral($0) }
                default:
                    break
                }
            }
            if let op = constantArithmeticOperator(name) {
                return literalConstantBinaryExpr(op: op, lhs: receiver, rhs: args[0].expr, ast: ast, interner: interner)
            }
            if name == "floorDiv" {
                return literalConstantFloorDiv(receiverConst, argument)
            }
            if name == "mod" {
                return literalConstantFloorMod(receiverConst, argument)
            }
            if name == "get",
               case let .stringLiteral(value) = receiverConst,
               case let .intLiteral(index) = argument
            {
                let utf16 = Array(interner.resolve(value).utf16)
                guard index >= 0, index < Int64(utf16.count) else { return nil }
                return .charLiteral(UInt32(utf16[Int(index)]))
            }
        }
        guard args.isEmpty else { return nil }
        switch name {
        case "toString" where canFoldMemberCall != nil:
            guard let text = stringConcatOperandText(of: receiverConst, interner: interner) else { return nil }
            return .stringLiteral(interner.intern(text))
        case "unaryPlus" where canFoldMemberCall != nil:
            return positiveConstant(receiverConst)
        case "unaryMinus" where canFoldMemberCall != nil:
            return negatedConstant(receiverConst)
        case "length" where canFoldMemberCall != nil:
            if case let .stringLiteral(value) = receiverConst {
                return .intLiteral(Int64(interner.resolve(value).utf16.count))
            }
            return nil
        case "inv" where canFoldMemberCall != nil:
            switch receiverConst {
            case let .intLiteral(value): return .intLiteral(Int64(~Int32(truncatingIfNeeded: value)))
            case let .longLiteral(value): return .longLiteral(~value)
            default: return nil
            }
        case "not" where canFoldMemberCall != nil:
            if case let .boolLiteral(value) = receiverConst { return .boolLiteral(!value) }
            return nil
        case "code":
            if case let .charLiteral(scalar) = receiverConst {
                return .intLiteral(Int64(scalar))
            }
            return nil
        case "toByte", "toShort", "toInt":
            if name == "toInt", let value = floatingValue(of: receiverConst) {
                return .intLiteral(saturatedInteger(value, minimum: Int64(Int32.min), maximum: Int64(Int32.max)))
            }
            guard let value = integerValue(of: receiverConst) else { return nil }
            return .intLiteral(truncatedInteger(value, name: name))
        case "toLong":
            if let value = floatingValue(of: receiverConst) {
                return .longLiteral(saturatedInteger(value, minimum: Int64.min, maximum: Int64.max))
            }
            guard let value = integerValue(of: receiverConst) else { return nil }
            return .longLiteral(value)
        case "toFloat":
            switch receiverConst {
            case let .intLiteral(value): return .floatLiteral(Double(Float(value)))
            case let .longLiteral(value): return .floatLiteral(Double(Float(value)))
            case let .charLiteral(value): return .floatLiteral(Double(Float(value)))
            case let .floatLiteral(value): return .floatLiteral(Double(Float(value)))
            case let .doubleLiteral(value): return .floatLiteral(Double(Float(value)))
            default: return nil
            }
        case "toDouble":
            switch receiverConst {
            case let .intLiteral(value): return .doubleLiteral(Double(value))
            case let .longLiteral(value): return .doubleLiteral(Double(value))
            case let .charLiteral(value): return .doubleLiteral(Double(value))
            case let .floatLiteral(value): return .doubleLiteral(Double(Float(value)))
            case let .doubleLiteral(value): return .doubleLiteral(value)
            default: return nil
            }
        case "toChar":
            guard let value = integerValue(of: receiverConst) else { return nil }
            return .charLiteral(UInt32(UInt16(truncatingIfNeeded: value)))
        default:
            return nil
        }
    }

    private func literalConstantCompareTo(_ lhs: KIRExprKind, _ rhs: KIRExprKind, interner: StringInterner) -> KIRExprKind? {
        let result: Int64? = switch (lhs, rhs) {
        case let (.boolLiteral(left), .boolLiteral(right)):
            compare(left ? 1 : 0, right ? 1 : 0)
        case let (.charLiteral(left), .charLiteral(right)):
            compare(Int64(left), Int64(right))
        case let (.stringLiteral(left), .stringLiteral(right)):
            // Kotlin String.compareTo is JVM String.compareTo: lexicographic
            // on UTF-16 code units, returning the unit/length difference.
            compareUTF16Strings(interner.resolve(left), interner.resolve(right))
        case let (.intLiteral(left), .intLiteral(right)), let (.intLiteral(left), .longLiteral(right)),
             let (.longLiteral(left), .intLiteral(right)), let (.longLiteral(left), .longLiteral(right)):
            compare(left, right)
        case let (.uintLiteral(left), .uintLiteral(right)), let (.uintLiteral(left), .ulongLiteral(right)),
             let (.ulongLiteral(left), .uintLiteral(right)), let (.ulongLiteral(left), .ulongLiteral(right)):
            compare(left, right)
        case let (.floatLiteral(left), .floatLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.doubleLiteral(left), .doubleLiteral(right)):
            compareFloatingPoint(left, right)
        case let (.floatLiteral(left), .doubleLiteral(right)):
            compareFloatingPoint(Double(Float(left)), right)
        case let (.doubleLiteral(left), .floatLiteral(right)):
            compareFloatingPoint(left, Double(Float(right)))
        case let (.intLiteral(left), .floatLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.longLiteral(left), .floatLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.uintLiteral(left), .floatLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.ulongLiteral(left), .floatLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.floatLiteral(left), .intLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.floatLiteral(left), .longLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.floatLiteral(left), .uintLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.floatLiteral(left), .ulongLiteral(right)):
            compareFloatingPoint(Float(left), Float(right))
        case let (.intLiteral(left), .doubleLiteral(right)):
            compareFloatingPoint(Double(left), right)
        case let (.longLiteral(left), .doubleLiteral(right)):
            compareFloatingPoint(Double(left), right)
        case let (.uintLiteral(left), .doubleLiteral(right)):
            compareFloatingPoint(Double(left), right)
        case let (.ulongLiteral(left), .doubleLiteral(right)):
            compareFloatingPoint(Double(left), right)
        case let (.doubleLiteral(left), .intLiteral(right)):
            compareFloatingPoint(left, Double(right))
        case let (.doubleLiteral(left), .longLiteral(right)):
            compareFloatingPoint(left, Double(right))
        case let (.doubleLiteral(left), .uintLiteral(right)):
            compareFloatingPoint(left, Double(right))
        case let (.doubleLiteral(left), .ulongLiteral(right)):
            compareFloatingPoint(left, Double(right))
        default:
            nil
        }
        return result.map(KIRExprKind.intLiteral)
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> Int64 {
        if lhs == rhs { return 0 }
        return lhs < rhs ? -1 : 1
    }

    /// JVM `String.compareTo` ordering: lexicographic over UTF-16 code units;
    /// the result is the first differing unit's difference or the length
    /// difference, not a normalized -1/0/1.
    private func compareUTF16Strings(_ lhs: String, _ rhs: String) -> Int64 {
        let lhsUnits = Array(lhs.utf16)
        let rhsUnits = Array(rhs.utf16)
        let sharedCount = min(lhsUnits.count, rhsUnits.count)
        for index in 0 ..< sharedCount where lhsUnits[index] != rhsUnits[index] {
            return Int64(lhsUnits[index]) - Int64(rhsUnits[index])
        }
        return Int64(lhsUnits.count - rhsUnits.count)
    }

    private func compareFloatingPoint<T: BinaryFloatingPoint>(_ lhs: T, _ rhs: T) -> Int64 {
        if lhs.isNaN { return rhs.isNaN ? 0 : 1 }
        if rhs.isNaN { return -1 }
        if lhs == rhs {
            if lhs == 0, lhs.sign != rhs.sign {
                return lhs.sign == .minus ? -1 : 1
            }
            return 0
        }
        return lhs < rhs ? -1 : 1
    }

    private func trimIndentString(_ text: String) -> String {
        let lines = trimBlankEdges(from: splitLines(text))
        var minimumIndent = Int.max
        for line in lines where !isKotlinBlank(line) {
            minimumIndent = min(minimumIndent, leadingKotlinWhitespaceCount(in: line))
        }
        if minimumIndent == Int.max {
            minimumIndent = 0
        }
        return joinLines(lines.map { line in
            Array(line.dropFirst(min(minimumIndent, line.count)))
        })
    }

    private func trimMarginString(_ text: String, prefix: [UInt16]) -> String {
        let lines = trimBlankEdges(from: splitLines(text))
        let trimmedLines = lines.map { line -> [UInt16] in
            let indentation = leadingKotlinWhitespaceCount(in: line)
            let prefixEnd = indentation + prefix.count
            guard indentation < line.count,
                  prefixEnd <= line.count,
                  Array(line[indentation ..< prefixEnd]) == prefix
            else {
                return line
            }
            return Array(line.dropFirst(prefixEnd))
        }
        return joinLines(trimmedLines)
    }

    private func splitLines(_ text: String) -> [[UInt16]] {
        let units = Array(text.utf16)
        var lines: [[UInt16]] = [[]]
        var index = 0
        while index < units.count {
            switch units[index] {
            case 0x000D:
                if index + 1 < units.count, units[index + 1] == 0x000A {
                    index += 1
                }
                lines.append([])
            case 0x000A:
                lines.append([])
            default:
                lines[lines.count - 1].append(units[index])
            }
            index += 1
        }
        return lines
    }

    private func trimBlankEdges(from lines: [[UInt16]]) -> [[UInt16]] {
        var start = 0
        var end = lines.count
        if start < end, isKotlinBlank(lines[start]) {
            start += 1
        }
        if end > start, isKotlinBlank(lines[end - 1]) {
            end -= 1
        }
        return Array(lines[start ..< end])
    }

    private func isKotlinBlank(_ units: [UInt16]) -> Bool {
        units.allSatisfy(isKotlinWhitespace)
    }

    private func leadingKotlinWhitespaceCount(in units: [UInt16]) -> Int {
        units.prefix(while: isKotlinWhitespace).count
    }

    private func isKotlinWhitespace(_ unit: UInt16) -> Bool {
        if (0x0009 ... 0x000D).contains(unit) || (0x001C ... 0x001F).contains(unit) {
            return true
        }
        guard let scalar = Unicode.Scalar(Int(unit)) else { return false }
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return false
        }
    }

    private func joinLines(_ lines: [[UInt16]]) -> String {
        var result: [UInt16] = []
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(0x000A)
            }
            result.append(contentsOf: line)
        }
        return String(decoding: result, as: UTF16.self)
    }

    private func constantArithmeticOperator(_ name: String) -> BinaryOp? {
        switch name {
        case "plus": .add
        case "minus": .subtract
        case "times": .multiply
        case "div": .divide
        case "rem": .modulo
        default: nil
        }
    }

    private func literalConstantFloorDiv(_ lhs: KIRExprKind, _ rhs: KIRExprKind) -> KIRExprKind? {
        switch (lhs, rhs) {
        case let (.intLiteral(left), .intLiteral(right)):
            return integerFloorDiv(left, right, width: 32).map { .intLiteral($0) }
        case let (.longLiteral(left), .longLiteral(right)):
            return integerFloorDiv(left, right).map { .longLiteral($0) }
        case let (.longLiteral(left), .intLiteral(right)), let (.intLiteral(left), .longLiteral(right)):
            return integerFloorDiv(left, right).map { .longLiteral($0) }
        default:
            return nil
        }
    }

    private func literalConstantFloorMod(_ lhs: KIRExprKind, _ rhs: KIRExprKind) -> KIRExprKind? {
        switch (lhs, rhs) {
        case let (.intLiteral(left), .intLiteral(right)):
            return integerFloorMod(left, right, width: 32).map { .intLiteral($0) }
        case let (.longLiteral(left), .longLiteral(right)), let (.intLiteral(left), .longLiteral(right)):
            return integerFloorMod(left, right).map { .longLiteral($0) }
        // `Long.mod(Int)` returns Int: the result is bounded by the Int divisor.
        case let (.longLiteral(left), .intLiteral(right)):
            return integerFloorMod(left, right).map { .intLiteral($0) }
        case let (.floatLiteral(left), .floatLiteral(right)):
            return floatingFloorMod(Float(left), Float(right)).map { .floatLiteral(Double($0)) }
        case let (.doubleLiteral(left), .doubleLiteral(right)):
            return floatingFloorMod(left, right).map { .doubleLiteral($0) }
        // `Float.mod(Double)` / `Double.mod(Float)` widen to Double like the
        // stdlib overloads do.
        case let (.floatLiteral(left), .doubleLiteral(right)):
            return floatingFloorMod(Double(Float(left)), right).map { .doubleLiteral($0) }
        case let (.doubleLiteral(left), .floatLiteral(right)):
            return floatingFloorMod(left, Double(Float(right))).map { .doubleLiteral($0) }
        default:
            return nil
        }
    }

    private func integerFloorDiv(_ lhs: Int64, _ rhs: Int64, width: Int = 64) -> Int64? {
        guard rhs != 0 else { return nil }
        let minimum = width == 32 ? Int64(Int32.min) : Int64.min
        if lhs == minimum, rhs == -1 { return minimum }
        let quotient = lhs / rhs
        let remainder = lhs % rhs
        let rounded = remainder != 0 && (lhs < 0) != (rhs < 0) ? quotient &- 1 : quotient
        return width == 32 ? Int64(Int32(truncatingIfNeeded: rounded)) : rounded
    }

    private func integerFloorMod(_ lhs: Int64, _ rhs: Int64, width: Int = 64) -> Int64? {
        guard rhs != 0 else { return nil }
        let minimum = width == 32 ? Int64(Int32.min) : Int64.min
        if lhs == minimum, rhs == -1 { return 0 }
        let remainder = lhs % rhs
        let adjusted = remainder != 0 && (remainder < 0) != (rhs < 0) ? remainder &+ rhs : remainder
        return width == 32 ? Int64(Int32(truncatingIfNeeded: adjusted)) : adjusted
    }

    /// An infinite divisor still takes the sign-correction branch: Kotlin's
    /// `(-1.0).mod(Double.POSITIVE_INFINITY)` is `Infinity`, not `-1.0`.
    private func floatingFloorMod<T: BinaryFloatingPoint>(_ lhs: T, _ rhs: T) -> T? {
        // Kotlin: `if (r != 0.0 && r.sign != other.sign) r + other else r`.
        // An infinite divisor still takes the adjustment: (-1.0).mod(+Inf) is +Inf.
        let remainder = lhs.truncatingRemainder(dividingBy: rhs)
        guard remainder != 0, !remainder.isNaN, (remainder < 0) != (rhs < 0) else {
            return remainder
        }
        return remainder + rhs
    }

    private func constantBitwiseOperator(_ name: String) -> BinaryOp? {
        switch name {
        case "and": .bitwiseAnd
        case "or": .bitwiseOr
        case "xor": .bitwiseXor
        case "shl": .shl
        case "shr": .shr
        case "ushr": .ushr
        default: nil
        }
    }

    func convertConstant(_ constant: KIRExprKind, to type: TypeID, types: TypeSystem) -> KIRExprKind {
        guard let value = integerValue(of: constant),
              case let .primitive(primitive, _) = types.kind(of: type)
        else { return constant }
        switch primitive {
        case .byte: return .intLiteral(Int64(Int8(truncatingIfNeeded: value)))
        case .short: return .intLiteral(Int64(Int16(truncatingIfNeeded: value)))
        case .int: return .intLiteral(Int64(Int32(truncatingIfNeeded: value)))
        case .long: return .longLiteral(value)
        default: return constant
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

    private func floatingValue(of constant: KIRExprKind) -> Double? {
        switch constant {
        case let .floatLiteral(v): Double(Float(v))
        case let .doubleLiteral(v): v
        default: nil
        }
    }

    /// `Double.toInt()`/`toLong()`: truncate toward zero, NaN becomes 0, and
    /// out-of-range values saturate (matches `__kk_double_to_int`).
    private func saturatedInteger(_ value: Double, minimum: Int64, maximum: Int64) -> Int64 {
        if value.isNaN { return 0 }
        if value >= Double(maximum) { return maximum }
        if value <= Double(minimum) { return minimum }
        return Int64(value)
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
    private func literalConstantStringTemplate(_ parts: [StringTemplatePart]) -> KIRExprKind? {
        guard parts.count == 1, case let .literal(text) = parts[0] else {
            return nil
        }
        return .stringLiteral(text)
    }

    /// Kotlin/JVM text of a compile-time constant operand inside a String `+`
    /// concatenation. Kotlin folds a `+` whose result is String only when
    /// every operand is a compile-time constant — literals, constant
    /// expressions, and `const val` reads, but never a plain `val`/`var`
    /// even with a literal initializer — so the caller must supply const
    /// resolution through `resolvedConstant` and nothing else. A `nil`
    /// result means the whole concatenation is not constant and must go
    /// through `__kk_string_concat_flat` at runtime (KUU-1385).
    func constantStringConcatOperandText(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        if case .nullLiteral = ast.arena.expr(exprID) {
            return "null"
        }
        if let constant = literalConstantExpr(exprID, ast: ast, interner: interner) {
            return stringConcatOperandText(of: constant, interner: interner)
        }
        switch ast.arena.expr(exprID) {
        case .binary(.add, let lhs, let rhs, _)?:
            // Mixed-type concat (`"a" + 5`): literalConstantBinaryExpr only
            // folds same-type pairs, so descend and fold each operand. A
            // nested `+` bound to a user-declared operator returning String
            // (e.g. `Int.plus(String)`) is not concat text — folding it would
            // drop the resolved call, so the subtree is not a constant.
            // A numeric `+` that literalConstantExpr could not fold (e.g.
            // `1u + 2u`) has no call binding either; it is arithmetic, not
            // concat, and must not be rendered as "12".
            guard sema.bindings.exprType(for: exprID) == sema.types.stringType,
                  Self.isBuiltinStringPlusCallee(exprID, sema: sema, interner: interner),
                  let lhsText = constantStringConcatOperandText(lhs, ast: ast, sema: sema, interner: interner),
                  let rhsText = constantStringConcatOperandText(rhs, ast: ast, sema: sema, interner: interner)
            else {
                return nil
            }
            return lhsText + rhsText
        case let .memberCall(receiver, callee, _, args, _)?:
            guard interner.resolve(callee) == "plus", args.count == 1,
                  Self.isBuiltinStringPlusCallee(exprID, sema: sema, interner: interner),
                  let receiverText = constantStringConcatOperandText(receiver, ast: ast, sema: sema, interner: interner),
                  let argumentText = constantStringConcatOperandText(args[0].expr, ast: ast, sema: sema, interner: interner)
            else {
                return nil
            }
            return receiverText + argumentText
        case .stringTemplate(let parts, _)?:
            // JVM folds a template whose interpolated expressions are all
            // compile-time constants (`"a" + "${5}"` == "a5").
            var text = ""
            for part in parts {
                switch part {
                case let .literal(literalText):
                    text += interner.resolve(literalText)
                case let .expression(partExpr):
                    guard let partText = constantStringConcatOperandText(partExpr, ast: ast, sema: sema, interner: interner)
                    else {
                        return nil
                    }
                    text += partText
                }
            }
            return text
        default:
            return nil
        }
    }

    /// Whether a `+` expression models Kotlin's built-in string
    /// concatenation for constant-folding purposes: true only when Sema left
    /// it unbound (the lenient built-in concat path) or bound it to the
    /// stdlib `String.plus` member or the `kotlin.text.String?.plus` facade.
    /// A user-declared operator that merely returns String keeps its resolved
    /// call. Shared by `ConstantCollector` and `CallLowerer`.
    static func isBuiltinStringPlusCallee(
        _ exprID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let chosenCallee = sema.bindings.callBindings[exprID]?.chosenCallee,
              let symbol = sema.symbols.symbol(chosenCallee)
        else {
            return true
        }
        let kotlinName = interner.intern("kotlin")
        let plusName = interner.intern("plus")
        return symbol.fqName == [kotlinName, interner.intern("String"), plusName]
            || symbol.fqName == [kotlinName, interner.intern("text"), plusName]
    }

    static func isBuiltinStringIndentTrimCall(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .memberCall(receiver, callee, typeArgs, args, _) = ast.arena.expr(exprID),
              typeArgs.isEmpty,
              let receiverType = sema.bindings.exprType(for: receiver),
              receiverType == sema.types.stringType,
              let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
              let symbol = sema.symbols.symbol(chosenCallee),
              let signature = sema.symbols.functionSignature(for: chosenCallee),
              signature.receiverType == sema.types.stringType
        else {
            return false
        }
        let name = interner.resolve(callee)
        guard ["trimIndent", "trimMargin"].contains(name),
              symbol.fqName == ["kotlin", "text", name].map(interner.intern)
        else {
            return false
        }
        switch name {
        case "trimIndent":
            return args.isEmpty
        case "trimMargin":
            return args.count <= 1 && args.allSatisfy { !$0.isSpread }
        default:
            return false
        }
    }

    private func stringConcatOperandText(
        of constant: KIRExprKind,
        interner: StringInterner
    ) -> String? {
        switch constant {
        case let .stringLiteral(value):
            return interner.resolve(value)
        case let .intLiteral(value), let .longLiteral(value):
            return String(value)
        case let .uintLiteral(value), let .ulongLiteral(value):
            return String(value)
        case let .charLiteral(value):
            guard let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        case let .boolLiteral(value):
            return value ? "true" : "false"
        case let .doubleLiteral(value):
            return kotlinFloatingPointConcatText(value)
        case let .floatLiteral(value):
            return kotlinFloatingPointConcatText(Float(value))
        default:
            return nil
        }
    }

    /// Java `Double.toString`/`Float.toString`-compatible rendering for
    /// compile-time folding. Mirrors `runtimeFormatFloatingPoint` in the
    /// runtime: Kotlin emits scientific notation for magnitudes >= 1e7 or
    /// < 1e-3, always with a decimal point in the mantissa.
    private func kotlinFloatingPointConcatText(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Infinity" }
        if value == -.infinity { return "-Infinity" }
        if value == 0.0 && value.sign == .minus { return "-0.0" }
        let magnitude = abs(value)
        let subnormalUnits = magnitude / Double.leastNonzeroMagnitude
        if magnitude != 0, subnormalUnits <= 20 {
            return javaSmallSubnormalConcatText(
                units: subnormalUnits * 4.9406564584124654, unitExponent: -324, isNegative: value < 0
            )
        }
        return finishFloatingPointConcatText(
            rendered: String(describing: value),
            useScientific: magnitude != 0 && (magnitude >= 1e7 || magnitude < 1e-3)
        )
    }

    private func kotlinFloatingPointConcatText(_ value: Float) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Infinity" }
        if value == -.infinity { return "-Infinity" }
        if value == 0.0 && value.sign == .minus { return "-0.0" }
        let magnitude = abs(value)
        let subnormalUnits = magnitude / Float.leastNonzeroMagnitude
        if magnitude != 0, subnormalUnits <= 71 {
            return javaSmallSubnormalConcatText(
                units: Double(subnormalUnits) * 1.4012984643248171, unitExponent: -45, isNegative: value < 0
            )
        }
        return finishFloatingPointConcatText(
            rendered: String(describing: value),
            useScientific: magnitude != 0 && (magnitude >= 1e7 || magnitude < 1e-3)
        )
    }

    /// Mirrors `runtimeJavaSmallSubnormalText`: JDK 19+ prints subnormals
    /// below 1e-322 (Float: 1e-43) with the closest two-digit decimal.
    private func javaSmallSubnormalConcatText(units: Double, unitExponent: Int, isNegative: Bool) -> String {
        let tenths = (units * 10).rounded()
        let (digits, exponent) = tenths < 100
            ? (Int(tenths), unitExponent)
            : (Int(units.rounded()), unitExponent + 1)
        return "\(isNegative ? "-" : "")\(digits / 10).\(digits % 10)E\(exponent)"
    }

    private func finishFloatingPointConcatText(rendered: String, useScientific: Bool) -> String {
        if rendered.contains("e") || rendered.contains("E") {
            return normalizeScientificConcatText(rendered)
        }
        if useScientific {
            return scientificConcatText(fromFixed: rendered)
        }
        return rendered
    }

    private func normalizeScientificConcatText(_ rendered: String) -> String {
        guard let exponentIndex = rendered.firstIndex(of: "E") ?? rendered.firstIndex(of: "e") else {
            return rendered
        }
        let mantissa = normalizeScientificConcatMantissa(String(rendered[..<exponentIndex]))
        var exponent = String(rendered[rendered.index(after: exponentIndex)...])
        if exponent.hasPrefix("+") {
            exponent.removeFirst()
        }
        while exponent.count > 1, exponent.first == "0" {
            exponent.removeFirst()
        }
        if exponent.hasPrefix("-0"), exponent.count > 2 {
            exponent.remove(at: exponent.index(after: exponent.startIndex))
        }
        return "\(mantissa)E\(exponent)"
    }

    private func normalizeScientificConcatMantissa(_ mantissa: String) -> String {
        guard let dotIndex = mantissa.firstIndex(of: ".") else {
            return mantissa + ".0"
        }
        let integerPart = String(mantissa[..<dotIndex])
        var fractionalPart = String(mantissa[mantissa.index(after: dotIndex)...])
        while fractionalPart.last == "0" {
            fractionalPart.removeLast()
        }
        if fractionalPart.isEmpty {
            fractionalPart = "0"
        }
        return "\(integerPart).\(fractionalPart)"
    }

    private func scientificConcatText(fromFixed rendered: String) -> String {
        var body = rendered
        var sign = ""
        if body.hasPrefix("-") {
            sign = "-"
            body.removeFirst()
        } else if body.hasPrefix("+") {
            body.removeFirst()
        }

        let components = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = String(components.first ?? "")
        let fractionalPart = components.count > 1 ? String(components[1]) : ""

        let trimmedInteger = integerPart.drop(while: { $0 == "0" })
        let exponent: Int
        let significantDigits: String

        if !trimmedInteger.isEmpty {
            exponent = trimmedInteger.count - 1
            significantDigits = String(trimmedInteger) + fractionalPart
        } else if let firstNonZeroFraction = fractionalPart.firstIndex(where: { $0 != "0" }) {
            exponent = -fractionalPart.distance(from: fractionalPart.startIndex, to: firstNonZeroFraction) - 1
            significantDigits = String(fractionalPart[firstNonZeroFraction...])
        } else {
            return sign + "0.0E0"
        }

        let firstDigit = String(significantDigits.prefix(1))
        var mantissaFraction = String(significantDigits.dropFirst())
        while mantissaFraction.last == "0" {
            mantissaFraction.removeLast()
        }
        if mantissaFraction.isEmpty {
            mantissaFraction = "0"
        }
        return "\(sign)\(firstDigit).\(mantissaFraction)E\(exponent)"
    }

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
        case let .intLiteral(v): .intLiteral(Int64(Int32(truncatingIfNeeded: 0 &- v)))
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
