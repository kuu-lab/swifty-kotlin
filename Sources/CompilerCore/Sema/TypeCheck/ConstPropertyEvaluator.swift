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

    /// Share the language's primitive/String constant rules with annotation values.
    func constantExpression(_ expression: ExprID) -> KIRExprKind? {
        let collector = ConstantCollector(
            resolvedConstant: { [self] expr in resolvedConstant(for: expr) },
            canFoldMemberCall: { [self] expr in canFoldMemberCall(expr) }
        )
        if let value = collector.literalConstantExpr(expression, ast: ast, interner: interner) { return value }
        if sema.bindings.exprType(for: expression) == sema.types.stringType,
           let text = collector.constantStringConcatOperandText(expression, ast: ast, sema: sema, interner: interner) {
            return .stringLiteral(interner.intern(text))
        }
        return nil
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
        guard let value = constantExpression(initializer) else {
            failed.insert(symbol)
            return nil
        }
        let type = sema.symbols.propertyType(for: symbol) ?? sema.types.nullableAnyType
        let collector = ConstantCollector()
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
        // `s[i]` desugars to the String.get operator; only the bundled
        // kotlin.text.get declaration is foldable.
        if case let .indexedAccess(receiver, indices, _) = ast.arena.expr(expr) {
            guard indices.count == 1,
                  let receiverType = sema.bindings.exprType(for: receiver),
                  sema.types.makeNonNullable(receiverType) == sema.types.stringType,
                  let indexType = sema.bindings.exprType(for: indices[0]),
                  sema.types.makeNonNullable(indexType) == sema.types.intType
            else {
                return false
            }
            return isBuiltinStringGetCall(expr)
        }
        guard case let .memberCall(receiver, callee, _, args, _) = ast.arena.expr(expr) else { return false }
        let name = interner.resolve(callee)
        guard let receiverType = sema.bindings.exprType(for: receiver) else { return false }
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)

        // kotlinc's constant evaluator never treats an unsigned value as a
        // compile-time constant: every member call on an unsigned receiver is
        // rejected even when the result is a signed primitive or a String
        // (`1u.compareTo(2u)`, `1u.toString()`). Unsigned literals may still
        // appear as String `+` operands, which does not go through this gate.
        if isUnsignedPrimitiveType(nonNullReceiverType) { return false }

        if name == "plus", nonNullReceiverType == sema.types.stringType {
            return args.count == 1
                && ConstantCollector.isBuiltinStringPlusCallee(expr, sema: sema, interner: interner)
        }
        if name == "length", nonNullReceiverType == sema.types.stringType {
            return args.isEmpty && isBuiltinStringLengthProperty(expr)
        }
        if name == "get", nonNullReceiverType == sema.types.stringType {
            return args.count == 1
                && !args[0].isSpread
                && sema.bindings.exprType(for: args[0].expr) == sema.types.intType
                && isBuiltinStringGetCall(expr)
        }
        if name == "code" {
            return args.isEmpty
                && nonNullReceiverType == sema.types.charType
                && (!isSourceBackedMemberExtensionCall(expr) || isBuiltinCharCodeProperty(expr))
        }
        // `Double.toInt()` & co. are source-backed `kotlin.*` extensions, but
        // kotlinc still evaluates them in `const val` initializers.
        if ["toInt", "toLong", "toFloat", "toDouble"].contains(name), isFloatingPrimitiveType(nonNullReceiverType) {
            guard args.isEmpty else { return false }
            guard isSourceBackedMemberExtensionCall(expr) else { return true }
            let resultType = switch name {
            case "toInt": sema.types.intType
            case "toLong": sema.types.longType
            case "toFloat": sema.types.floatType
            default: sema.types.doubleType
            }
            return isBuiltinKotlinNumericConversion(
                expr,
                name: name,
                receiverType: nonNullReceiverType,
                resultType: resultType
            )
        }
        if name == "toFloat" || name == "toDouble" {
            guard args.isEmpty,
                  isIntegerPrimitiveType(nonNullReceiverType)
                      || nonNullReceiverType == sema.types.charType
            else { return false }
            guard isSourceBackedMemberExtensionCall(expr) else { return true }
            let resultType = name == "toFloat" ? sema.types.floatType : sema.types.doubleType
            return isBuiltinKotlinNumericConversion(
                expr,
                name: name,
                receiverType: nonNullReceiverType,
                resultType: resultType
            )
        }
        // `Int.toChar` is the only non-deprecated numeric->Char conversion; the
        // bundled stdlib declares it as a kotlin-package extension. Long/Float/
        // Double.toChar are deprecated at error level upstream and stay
        // rejected here until the bundled metadata carries that deprecation.
        if name == "toChar" {
            guard args.isEmpty, isNumericPrimitiveType(nonNullReceiverType) else { return false }
            guard isSourceBackedMemberExtensionCall(expr) else { return true }
            return nonNullReceiverType == sema.types.intType
                && isBuiltinKotlinNumericConversion(
                    expr,
                    name: name,
                    receiverType: nonNullReceiverType,
                    resultType: sema.types.charType
                )
        }
        if name == "compareTo" {
            guard args.count == 1,
                  let argumentType = sema.bindings.exprType(for: args[0].expr),
                  isSupportedPrimitiveComparison(nonNullReceiverType, argumentType)
            else { return false }
            return !isSourceBackedMemberExtensionCall(expr)
                || isBuiltinKotlinComparableMemberCall(expr)
                || isBuiltinKotlinPrimitiveExtensionCall(expr, name: name, receiverType: nonNullReceiverType)
                || isBuiltinStringCompareToCall(expr)
        }
        if name == "toString" {
            return args.isEmpty
                && (isPrimitiveType(nonNullReceiverType)
                    || nonNullReceiverType == sema.types.stringType)
                && !isSourceBackedMemberExtensionCall(expr)
        }
        if name == "unaryPlus" || name == "unaryMinus" {
            return args.isEmpty && isSignedNumericPrimitiveType(nonNullReceiverType)
                && isBuiltinKotlinPrimitiveExtensionCall(expr, name: name, receiverType: nonNullReceiverType)
        }
        guard !isSourceBackedMemberExtensionCall(expr) else { return false }
        if name == "not" {
            return args.isEmpty && nonNullReceiverType == sema.types.booleanType
        }
        if name == "inv" {
            return args.isEmpty
                && (nonNullReceiverType == sema.types.intType || nonNullReceiverType == sema.types.longType)
        }
        if ["and", "or", "xor"].contains(name) {
            guard args.count == 1, let argumentType = sema.bindings.exprType(for: args[0].expr) else { return false }
            let nonNullArgumentType = sema.types.makeNonNullable(argumentType)
            if nonNullReceiverType == sema.types.booleanType {
                return nonNullArgumentType == sema.types.booleanType
            }
            return (nonNullReceiverType == sema.types.intType || nonNullReceiverType == sema.types.longType)
                && nonNullArgumentType == nonNullReceiverType
        }
        if ["shl", "shr", "ushr"].contains(name) {
            guard args.count == 1,
                  nonNullReceiverType == sema.types.intType || nonNullReceiverType == sema.types.longType,
                  let argumentType = sema.bindings.exprType(for: args[0].expr)
            else { return false }
            return sema.types.makeNonNullable(argumentType) == sema.types.intType
        }
        if ["plus", "minus", "times", "div", "rem", "mod", "floorDiv"].contains(name) {
            guard args.count == 1, isNumericPrimitiveType(nonNullReceiverType),
                  let argumentType = sema.bindings.exprType(for: args[0].expr)
            else { return false }
            return isNumericPrimitiveType(argumentType)
        }
        if ["toByte", "toShort", "toInt", "toLong", "toChar"].contains(name) {
            return args.isEmpty && isNumericPrimitiveType(nonNullReceiverType)
        }
        return false
    }

    private func isBuiltinStringLengthProperty(_ expr: ExprID) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              let calleeSymbol = sema.symbols.symbol(callee)
        else { return false }
        let propertySymbol = sema.symbols.accessorOwnerProperty(for: callee)
            ?? (calleeSymbol.kind == .property ? callee : sema.symbols.parentSymbol(for: callee))
        guard let propertySymbol,
              let property = sema.symbols.symbol(propertySymbol),
              property.kind == .property,
              property.name == interner.intern("length"),
              property.fqName == [interner.intern("kotlin"), interner.intern("length")],
              sema.symbols.extensionPropertyReceiverType(for: propertySymbol) == sema.types.stringType
        else { return false }
        return sema.symbols.isSourceBackedSymbol(propertySymbol)
    }

    private func isBuiltinStringGetCall(_ expr: ExprID) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              let symbol = sema.symbols.symbol(callee),
              symbol.kind == .function,
              symbol.fqName == ["kotlin", "text", "get"].map(interner.intern),
              sema.symbols.isSourceBackedSymbol(callee),
              let signature = sema.symbols.functionSignature(for: callee),
              signature.receiverType.map(sema.types.makeNonNullable) == sema.types.stringType,
              signature.parameterTypes == [sema.types.intType],
              signature.returnType == sema.types.charType
        else { return false }
        return true
    }

    private func isBuiltinKotlinNumericConversion(
        _ expr: ExprID,
        name: String,
        receiverType: TypeID,
        resultType: TypeID
    ) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              let symbol = sema.symbols.symbol(callee),
              symbol.kind == .function,
              symbol.fqName == ["kotlin", name].map(interner.intern),
              let signature = sema.symbols.functionSignature(for: callee),
              signature.receiverType.map(sema.types.makeNonNullable) == receiverType,
              signature.parameterTypes.isEmpty,
              signature.returnType == resultType
        else { return false }
        return sema.symbols.isSourceBackedSymbol(callee) || sema.symbols.isSyntheticStubSymbol(callee)
    }

    /// `kotlin.text.String.compareTo(String)` is a source-backed extension in
    /// the bundled stdlib; only that canonical declaration may fold, so a
    /// user extension of the same shape is never treated as constant.
    private func isBuiltinStringCompareToCall(_ expr: ExprID) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              let symbol = sema.symbols.symbol(callee),
              symbol.kind == .function,
              symbol.fqName == ["kotlin", "text", "compareTo"].map(interner.intern),
              sema.symbols.isSourceBackedSymbol(callee),
              let signature = sema.symbols.functionSignature(for: callee),
              signature.receiverType.map(sema.types.makeNonNullable) == sema.types.stringType,
              signature.parameterTypes == [sema.types.stringType],
              signature.returnType == sema.types.intType
        else { return false }
        return true
    }

    private func isBuiltinCharCodeProperty(_ expr: ExprID) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              let calleeSymbol = sema.symbols.symbol(callee)
        else { return false }
        let propertySymbol = sema.symbols.accessorOwnerProperty(for: callee)
            ?? (calleeSymbol.kind == .property ? callee : sema.symbols.parentSymbol(for: callee))
        guard let propertySymbol,
              let property = sema.symbols.symbol(propertySymbol),
              property.kind == .property,
              property.name == interner.intern("code"),
              property.fqName == [interner.intern("kotlin"), interner.intern("code")],
              sema.symbols.extensionPropertyReceiverType(for: propertySymbol) == sema.types.charType
        else { return false }
        return sema.symbols.isSourceBackedSymbol(propertySymbol)
    }

    private func isUnsignedPrimitiveType(_ type: TypeID) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.ubyte, _), .primitive(.ushort, _), .primitive(.uint, _), .primitive(.ulong, _):
            return true
        default:
            return false
        }
    }

    private func isNumericPrimitiveType(_ type: TypeID) -> Bool {
        guard case let .primitive(primitive, _) = sema.types.kind(of: sema.types.makeNonNullable(type)) else {
            return false
        }
        return primitive != .boolean
    }

    private func isIntegerPrimitiveType(_ type: TypeID) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.byte, _), .primitive(.short, _), .primitive(.int, _), .primitive(.long, _):
            return true
        default:
            return false
        }
    }

    private func isFloatingPrimitiveType(_ type: TypeID) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.float, _), .primitive(.double, _): true
        default: false
        }
    }

    private func isPrimitiveType(_ type: TypeID) -> Bool {
        if case .primitive = sema.types.kind(of: sema.types.makeNonNullable(type)) { return true }
        return false
    }

    private func isSignedNumericPrimitiveType(_ type: TypeID) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.byte, _), .primitive(.short, _), .primitive(.int, _),
             .primitive(.long, _), .primitive(.float, _), .primitive(.double, _):
            true
        default:
            false
        }
    }

    private func isSupportedPrimitiveComparison(_ receiverType: TypeID, _ argumentType: TypeID) -> Bool {
        let receiverType = sema.types.makeNonNullable(receiverType)
        let argumentType = sema.types.makeNonNullable(argumentType)
        if isSignedNumericPrimitiveType(receiverType), isSignedNumericPrimitiveType(argumentType) {
            return true
        }
        if receiverType == sema.types.stringType, argumentType == sema.types.stringType {
            return true
        }
        return receiverType == argumentType && isPrimitiveType(receiverType)
    }

    /// Unary signs and some primitive `compareTo` overloads are represented
    /// by source-backed extensions in the bundled `kotlin` package. Permit
    /// only those canonical declarations so user extensions are never folded.
    private func isBuiltinKotlinPrimitiveExtensionCall(
        _ expr: ExprID,
        name: String,
        receiverType: TypeID
    ) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              sema.symbols.isSourceBackedSymbol(callee),
              let symbol = sema.symbols.symbol(callee),
              symbol.fqName == [interner.intern("kotlin"), interner.intern(name)],
              let declaredReceiver = sema.symbols.functionSignature(for: callee)?.receiverType
        else { return false }
        return sema.types.makeNonNullable(declaredReceiver) == receiverType
    }

    private func isBuiltinKotlinComparableMemberCall(_ expr: ExprID) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              sema.symbols.isSourceBackedSymbol(callee),
              let symbol = sema.symbols.symbol(callee),
              symbol.kind == .function,
              symbol.fqName == [interner.intern("kotlin"), interner.intern("Comparable"), interner.intern("compareTo")],
              sema.symbols.parentSymbol(for: callee) == sema.types.comparableInterfaceSymbol
        else { return false }
        return true
    }

    private func isSourceBackedMemberExtensionCall(_ expr: ExprID) -> Bool {
        guard let callee = sema.bindings.callBinding(for: expr)?.chosenCallee,
              sema.symbols.isSourceBackedSymbol(callee),
              sema.symbols.symbol(callee)?.flags.contains(.synthetic) != true,
              sema.symbols.functionSignature(for: callee)?.receiverType != nil
        else {
            return false
        }
        return true
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
        let sizeBits: [String: Int64] = [
            "Byte": 8, "UByte": 8, "Short": 16, "UShort": 16, "Int": 32, "UInt": 32,
            "Float": 32, "Long": 64, "ULong": 64, "Double": 64,
        ]
        if let bits = sizeBits[path[1]], member == "SIZE_BITS" || member == "SIZE_BYTES" {
            return .intLiteral(member == "SIZE_BITS" ? bits : bits / 8)
        }
        switch (path[1], member) {
        case ("Char", "MIN_VALUE"): return .charLiteral(0)
        case ("Char", "MAX_VALUE"): return .charLiteral(65535)
        case ("Byte", "MIN_VALUE"): return .intLiteral(-128)
        case ("Byte", "MAX_VALUE"): return .intLiteral(127)
        case ("Short", "MIN_VALUE"): return .intLiteral(-32768)
        case ("Short", "MAX_VALUE"): return .intLiteral(32767)
        case ("Int", "MIN_VALUE"): return .intLiteral(Int64(Int32.min))
        case ("Int", "MAX_VALUE"): return .intLiteral(Int64(Int32.max))
        case ("Long", "MIN_VALUE"): return .longLiteral(Int64.min)
        case ("Long", "MAX_VALUE"): return .longLiteral(Int64.max)
        case ("UByte", "MIN_VALUE"), ("UShort", "MIN_VALUE"), ("UInt", "MIN_VALUE"):
            return .uintLiteral(0)
        case ("UByte", "MAX_VALUE"): return .uintLiteral(UInt64(UInt8.max))
        case ("UShort", "MAX_VALUE"): return .uintLiteral(UInt64(UInt16.max))
        case ("UInt", "MAX_VALUE"): return .uintLiteral(UInt64(UInt32.max))
        case ("ULong", "MIN_VALUE"): return .ulongLiteral(0)
        case ("ULong", "MAX_VALUE"): return .ulongLiteral(UInt64.max)
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
        default: return nil
        }
    }
}
