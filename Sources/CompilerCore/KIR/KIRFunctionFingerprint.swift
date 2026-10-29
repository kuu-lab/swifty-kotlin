import Foundation

/// A content hash of one KIR function that does not depend on how this
/// particular compilation happened to number things (KUU-3019, step 2 of the
/// declaration-level cache).
///
/// `SymbolID`, `TypeID`, `InternedString`, `KIRExprID` and label numbers are
/// all assigned in encounter order, so adding an unrelated function earlier in
/// the program shifts them and would change the hash of every later function.
/// The fingerprint therefore replaces each of them with a name-based form:
///
/// * symbols → kind + fully qualified name (+ erased signature for callables,
///   + an ordinal among same-keyed symbols so distinct symbols never merge);
/// * parameter symbols → their position in the function;
/// * types → a structural rendering that names classes by qualified name;
/// * expression ids and labels → numbered by first appearance in the body.
///
/// A fingerprint covers only the function itself. A cache consumer must also
/// mix in the fingerprints (or signatures) of everything in `references`, plus
/// the environment inputs listed in `docs/incremental-compilation.md`
/// (layout, vtable/itable slots, type tags, runtime ABI, stdlib artifact).
/// Source ranges are deliberately excluded; a consumer that embeds locations
/// in generated code must key on them separately.
public struct KIRFunctionFingerprint: Equatable, Sendable {
    /// Canonical identity of the function (symbol key, see above).
    public let key: String
    /// Hex SHA-256 of the canonical rendering.
    public let hash: String
    /// Canonical keys of the symbols the body calls or reads. Parameter
    /// symbols of the function itself are excluded.
    public let references: Set<String>
}

extension KIRModule {
    /// Fingerprints every function in the module, keyed by canonical key.
    /// If two functions still share a key after disambiguation (this should not
    /// happen), the later one is stored under `key#<n>` rather than dropped.
    public func functionFingerprints(
        interner: StringInterner,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [String: KIRFunctionFingerprint] {
        let canonicalizer = KIRCanonicalizer(arena: arena, interner: interner, symbols: symbols, types: types)
        var result: [String: KIRFunctionFingerprint] = [:]
        for decl in arena.declarations {
            guard case let .function(function) = decl else { continue }
            let fingerprint = canonicalizer.fingerprint(of: function)
            var key = fingerprint.key
            var duplicate = 1
            while result[key] != nil {
                key = "\(fingerprint.key)#\(duplicate)"
                duplicate += 1
            }
            result[key] = fingerprint
        }
        return result
    }
}

/// Renders KIR into a numbering-independent text form. One instance is shared
/// across a module so symbol and type renderings are computed once.
final class KIRCanonicalizer {
    private let arena: KIRArena
    private let interner: StringInterner
    private let symbols: SymbolTable
    private let types: TypeSystem
    private var symbolKeys: [SymbolID: String] = [:]
    private var typeKeys: [TypeID: String] = [:]
    /// Types currently being rendered; guards against cyclic captured bounds.
    private var typesInProgress: Set<TypeID> = []

    init(arena: KIRArena, interner: StringInterner, symbols: SymbolTable, types: TypeSystem) {
        self.arena = arena
        self.interner = interner
        self.symbols = symbols
        self.types = types
    }

    func fingerprint(of function: KIRFunction) -> KIRFunctionFingerprint {
        var body = FunctionRenderer(canonicalizer: self, function: function)
        let text = body.render()
        let hash = FileFingerprint.sha256Hex(Data(text.utf8))
        return KIRFunctionFingerprint(key: symbolKey(function.symbol), hash: hash, references: body.references)
    }

    // MARK: - Symbols

    func symbolKey(_ id: SymbolID) -> String {
        if let cached = symbolKeys[id] { return cached }
        let key = computeSymbolKey(id)
        symbolKeys[id] = key
        return key
    }

    private var baseKeys: [SymbolID: String] = [:]

    private func computeSymbolKey(_ id: SymbolID) -> String {
        // Not in the table: compiler-synthesized IDs (e.g. lambda parameters,
        // derived from the lambda's ExprID). Their raw value is the only
        // identity available; keeping it can over-invalidate when ExprIDs shift
        // but never merges two distinct synthetic symbols.
        guard let symbol = symbols.symbol(id) else { return "?synthetic#\(id.rawValue)" }
        let base = baseKey(of: symbol)
        // Distinct symbols can share a base key (two lambdas in one function,
        // overloads whose signatures erase equally, same-named type parameters
        // of different classes once ID-derived name parts are normalized).
        // Number them in definition order so they stay distinguishable, which
        // can only over-invalidate.
        let peers = candidates(fqName: symbol.fqName, shortName: symbol.name)
            .filter { baseKey(ofID: $0) == base }
            .sorted { $0.rawValue < $1.rawValue }
        guard peers.count > 1, let ordinal = peers.firstIndex(of: id) else { return base }
        return "\(base)#\(ordinal)"
    }

    /// Symbols that might share a key with one named `fqName`: those registered
    /// under the exact FQ name plus those with the same short name (the FQ
    /// name of some symbols contains an ID-derived part, and constructors are
    /// not in the short-name index).
    func candidates(fqName: [InternedString], shortName: InternedString) -> Set<SymbolID> {
        var result = Set(symbols.lookupAll(fqName: fqName))
        result.formUnion(symbols.lookupByShortName(shortName))
        return result
    }

    private func baseKey(ofID id: SymbolID) -> String? {
        if let cached = baseKeys[id] { return cached }
        guard let symbol = symbols.symbol(id) else { return nil }
        return baseKey(of: symbol)
    }

    /// Name components embed raw IDs for some compiler-created symbols (a class
    /// type parameter's FQ name contains `$class<SymbolID>`); drop the digits
    /// so the key does not move when unrelated declarations are added.
    static func normalizedComponent(_ component: String) -> String {
        guard component.hasPrefix("$") else { return component }
        var trimmed = Substring(component)
        while let last = trimmed.last, last.isNumber { trimmed = trimmed.dropLast() }
        return String(trimmed)
    }

    func normalizedFQName(of symbol: SemanticSymbol) -> [String] {
        symbol.fqName.map { Self.normalizedComponent(interner.resolve($0)) }
    }

    private func baseKey(of symbol: SemanticSymbol) -> String {
        if let cached = baseKeys[symbol.id] { return cached }
        var key = "\(symbol.kind)|" + normalizedFQName(of: symbol).joined(separator: ".")
        switch symbol.kind {
        case .function, .constructor:
            if let signature = symbols.functionSignatureIfKnown(for: symbol.id) {
                let receiver = signature.receiverType.map(typeKey) ?? "_"
                let params = signature.parameterTypes.map(typeKey).joined(separator: ",")
                key += "(\(receiver);\(params))\(typeKey(signature.returnType))"
            }
        case .property, .field, .backingField:
            if let type = symbols.propertyType(for: symbol.id) { key += ":\(typeKey(type))" }
        default:
            break
        }
        baseKeys[symbol.id] = key
        return key
    }

    // MARK: - Types

    func typeKey(_ id: TypeID) -> String {
        if let cached = typeKeys[id] { return cached }
        // A cycle can only come through captured-type bounds; cut it with the
        // raw id's structural kind so rendering always terminates.
        guard typesInProgress.insert(id).inserted else { return "<cycle>" }
        defer { typesInProgress.remove(id) }
        let key = renderType(types.kind(of: id))
        typeKeys[id] = key
        return key
    }

    private func nullabilityKey(_ nullability: Nullability) -> String {
        switch nullability {
        case .nonNull: ""
        case .nullable: "?"
        case .platformType: "!"
        }
    }

    private func renderType(_ kind: TypeKind) -> String {
        switch kind {
        case .error: return "error"
        case .unit: return "Unit"
        case .nullableUnit: return "Unit?"
        case .platformUnit: return "Unit!"
        case let .nothing(nullability): return "Nothing" + nullabilityKey(nullability)
        case let .any(nullability): return "Any" + nullabilityKey(nullability)
        case let .stringStruct(nullability): return "String" + nullabilityKey(nullability)
        case let .primitive(primitive, nullability): return primitive.rawValue + nullabilityKey(nullability)
        case let .classType(classType):
            var rendered = "class:" + symbolKey(classType.classSymbol)
            if !classType.args.isEmpty {
                rendered += "<" + classType.args.map(typeArgKey).joined(separator: ",") + ">"
            }
            if !classType.enclosingTypeArgs.isEmpty {
                rendered += "[" + classType.enclosingTypeArgs.map(typeArgKey).joined(separator: ",") + "]"
            }
            return rendered + nullabilityKey(classType.nullability)
        case let .typeParam(typeParam):
            var rendered = "tp:" + symbolKey(typeParam.symbol)
            if let capture = typeParam.capture {
                // `identity` is a per-inference counter; bounds carry the meaning.
                rendered += "{capture \(typeKey(capture.lower))..\(typeKey(capture.upper)) wf=\(capture.writeForbidden)}"
            }
            return rendered + nullabilityKey(typeParam.nullability)
        case let .functionType(functionType):
            let context = functionType.contextReceivers.map(typeKey).joined(separator: ",")
            let receiver = functionType.receiver.map(typeKey) ?? "_"
            let params = functionType.params.map(typeKey).joined(separator: ",")
            let thrown = functionType.throws.map(typeKey).joined(separator: ",")
            return "fn\(functionType.isSuspend ? "-suspend" : "")\(functionType.isCallableReference ? "-ref" : "")"
                + "(ctx[\(context)] recv \(receiver) (\(params)) -> \(typeKey(functionType.returnType)) throws[\(thrown)])"
                + nullabilityKey(functionType.nullability)
        case let .intersection(parts):
            return "&(" + parts.map(typeKey).joined(separator: ",") + ")"
        case let .kClassType(kClassType):
            return "KClass<\(typeKey(kClassType.argument))>" + nullabilityKey(kClassType.nullability)
        }
    }

    private func typeArgKey(_ arg: TypeArg) -> String {
        switch arg {
        case let .invariant(type): typeKey(type)
        case let .out(type): "out \(typeKey(type))"
        case let .in(type): "in \(typeKey(type))"
        case .star: "*"
        }
    }

    // MARK: - Function bodies

    /// Renders one function. Mutable because ids, labels and parameters are
    /// numbered as they are first met.
    struct FunctionRenderer {
        let canonicalizer: KIRCanonicalizer
        let function: KIRFunction
        var references: Set<String> = []
        private var exprNumbers: [KIRExprID: Int] = [:]
        private var labelNumbers: [Int32: Int] = [:]
        private var parameterIndexBySymbol: [SymbolID: Int] = [:]

        init(canonicalizer: KIRCanonicalizer, function: KIRFunction) {
            self.canonicalizer = canonicalizer
            self.function = function
            for (index, parameter) in function.params.enumerated() {
                parameterIndexBySymbol[parameter.symbol] = index
            }
        }

        mutating func render() -> String {
            let c = canonicalizer
            var lines: [String] = []
            let flags = [
                function.isSuspend ? "suspend" : nil,
                function.isInline ? "inline" : nil,
                function.isInlineOnly ? "inlineOnly" : nil,
                function.isTailrec ? "tailrec" : nil,
            ].compactMap { $0 }.joined(separator: ",")
            let params = function.params.map { c.typeKey($0.type) }.joined(separator: ",")
            lines.append("fun \(c.symbolKey(function.symbol)) name=\(c.interner.resolve(function.name)) flags=[\(flags)] params=[\(params)] ret=\(c.typeKey(function.returnType))")
            for instruction in function.body {
                lines.append(describe(instruction))
            }
            return lines.joined(separator: "\n")
        }

        // Expressions are numbered by first appearance, so the printed number
        // is a property of the body, not of the module-wide arena.
        private mutating func expr(_ id: KIRExprID) -> String {
            if id == .invalid { return "r!" }
            if let number = exprNumbers[id] { return "r\(number)" }
            let number = exprNumbers.count
            exprNumbers[id] = number
            return "r\(number)"
        }

        private mutating func optionalExpr(_ id: KIRExprID?) -> String {
            id.map { expr($0) } ?? "_"
        }

        private mutating func label(_ id: Int32) -> String {
            if let number = labelNumbers[id] { return "L\(number)" }
            let number = labelNumbers.count
            labelNumbers[id] = number
            return "L\(number)"
        }

        /// Type and arena-recorded kind of an expression the first time it is
        /// seen in an instruction operand position it defines.
        private mutating func annotatedExpr(_ id: KIRExprID) -> String {
            let isNew = exprNumbers[id] == nil
            let name = expr(id)
            guard isNew, id != .invalid else { return name }
            var annotation = name
            if let type = canonicalizer.arena.exprTypes[id] { annotation += ":\(canonicalizer.typeKey(type))" }
            let index = Int(id.rawValue)
            if index >= 0, index < canonicalizer.arena.expressions.count {
                let kind = canonicalizer.arena.expressions[index]
                // A bare `.temporary(n)` stores the id itself; it carries no meaning.
                if case .temporary = kind {} else { annotation += "=" + valueKey(kind) }
            }
            return annotation
        }

        private mutating func symbolKey(_ id: SymbolID) -> String {
            if let index = parameterIndexBySymbol[id] { return "param#\(index)" }
            let key = canonicalizer.symbolKey(id)
            references.insert(key)
            return key
        }

        private mutating func optionalSymbol(_ id: SymbolID?) -> String {
            id.map { symbolKey($0) } ?? "_"
        }

        private func resolve(_ string: InternedString) -> String {
            canonicalizer.interner.resolve(string)
        }

        private mutating func valueKey(_ value: KIRExprKind) -> String {
            switch value {
            case let .intLiteral(v): "int(\(v))"
            case let .longLiteral(v): "long(\(v))"
            case let .uintLiteral(v): "uint(\(v))"
            case let .ulongLiteral(v): "ulong(\(v))"
            // Bit patterns keep -0.0 and NaN payloads distinct.
            case let .floatLiteral(v): "float(\(v.bitPattern))"
            case let .doubleLiteral(v): "double(\(v.bitPattern))"
            case let .charLiteral(v): "char(\(v))"
            case let .boolLiteral(v): "bool(\(v))"
            case let .stringLiteral(s): "string(\(resolve(s).debugDescription))"
            case let .symbolRef(symbol): "ref(\(symbolKey(symbol)))"
            case let .externSymbolAddress(s): "extern(\(resolve(s).debugDescription))"
            case .temporary: "tmp"
            case .null: "null"
            case .unit: "unit"
            }
        }

        private mutating func returnTarget(_ target: KIRReturnTarget?) -> String {
            switch target {
            case .none: "_"
            case let .function(symbol): "fn(\(symbolKey(symbol)))"
            case let .importedFunction(name): "imported(\(resolve(name)))"
            }
        }

        private mutating func dispatchKey(_ dispatch: KIRDispatchKind) -> String {
            // Slot numbers are layout inputs: a layout change must change the hash.
            switch dispatch {
            case let .vtable(slot): "vtable[\(slot)]"
            case let .itable(interfaceSlot, methodSlot): "itable[\(interfaceSlot):\(methodSlot)]"
            case let .itableDynamic(interfaceTypeID, methodSlot): "itableDynamic[\(interfaceTypeID):\(methodSlot)]"
            }
        }

        private mutating func describe(_ instruction: KIRInstruction) -> String {
            switch instruction {
            case .nop: return "nop"
            case .beginBlock: return "beginBlock"
            case .endBlock: return "endBlock"
            case let .label(id): return "label \(label(id))"
            case let .jump(target): return "jump \(label(target))"
            case let .jumpIfEqual(lhs, rhs, target):
                return "jumpIfEqual \(expr(lhs)),\(expr(rhs)) -> \(label(target))"
            case let .constValue(result, value):
                return "const \(annotatedExpr(result)) \(valueKey(value))"
            case let .binary(op, lhs, rhs, result):
                return "binary \(op) \(expr(lhs)),\(expr(rhs)) -> \(annotatedExpr(result))"
            case let .unary(op, operand, result):
                return "unary \(op) \(expr(operand)) -> \(annotatedExpr(result))"
            case let .nullAssert(operand, result):
                return "nullAssert \(expr(operand)) -> \(annotatedExpr(result))"
            case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
                let args = arguments.map { annotatedExpr($0) }.joined(separator: ",")
                let ret = result.map { annotatedExpr($0) } ?? "_"
                let thrown = thrownResult.map { annotatedExpr($0) } ?? "_"
                return "call \(resolve(callee)) sym=\(optionalSymbol(symbol)) args=[\(args)] ret=\(ret) canThrow=\(canThrow) thrown=\(thrown) super=\(isSuperCall) qsuper=\(optionalSymbol(qualifiedSuperType))"
            case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
                let args = arguments.map { annotatedExpr($0) }.joined(separator: ",")
                let ret = result.map { annotatedExpr($0) } ?? "_"
                let thrown = thrownResult.map { annotatedExpr($0) } ?? "_"
                return "virtualCall \(resolve(callee)) sym=\(optionalSymbol(symbol)) recv=\(annotatedExpr(receiver)) args=[\(args)] ret=\(ret) canThrow=\(canThrow) thrown=\(thrown) dispatch=\(dispatchKey(dispatch))"
            case let .jumpIfNotNull(value, target):
                return "jumpIfNotNull \(expr(value)) -> \(label(target))"
            case let .copy(from, to):
                return "copy \(expr(from)) -> \(annotatedExpr(to))"
            case let .storeGlobal(value, symbol):
                return "storeGlobal \(expr(value)) -> \(symbolKey(symbol))"
            case let .loadGlobal(result, symbol):
                return "loadGlobal \(symbolKey(symbol)) -> \(annotatedExpr(result))"
            case let .rethrow(value): return "rethrow \(expr(value))"
            case let .returnIfEqual(lhs, rhs): return "returnIfEqual \(expr(lhs)),\(expr(rhs))"
            case .returnUnit: return "returnUnit"
            case let .returnValue(value): return "return \(expr(value))"
            case let .nonLocalReturn(value, target):
                return "nonLocalReturn \(optionalExpr(value)) target=\(returnTarget(target))"
            case let .beginNonLocalReturnScope(value, target, function):
                return "beginNonLocalReturnScope \(expr(value)),\(label(target)) fn=\(returnTarget(function))"
            case .endNonLocalReturnScope: return "endNonLocalReturnScope"
            case let .resumeNonLocalReturn(value): return "resumeNonLocalReturn \(expr(value))"
            case let .beginFinallyCleanup(skipping): return "beginFinallyCleanup skipping=\(skipping)"
            case .endFinallyCleanup: return "endFinallyCleanup"
            case .beginFinallyGuard: return "beginFinallyGuard"
            case .endFinallyGuard: return "endFinallyGuard"
            }
        }
    }
}
