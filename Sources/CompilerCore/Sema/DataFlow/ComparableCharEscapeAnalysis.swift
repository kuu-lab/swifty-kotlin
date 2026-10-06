/// KUU-1211: escape analysis for `Comparable<Char>` locals, mirroring the part
/// of kotlinc's boxing elimination that is observable through `compareTo`.
///
/// On the JVM a local statically typed `Comparable<Char>` (nullable or not)
/// whose value provably comes from `Char` is stored as a primitive `char`, so
/// `value.compareTo(other)` lowers to `Intrinsics.compare` and yields the
/// normalized -1/0/1. Once the value can flow into an object-typed position the
/// local is boxed and the same call produces the raw code-unit difference.
///
/// Escape is storage-wide and propagates through plain copies
/// (`val d2 = d` / `d2 = d` between `Comparable<Char>` locals) in both
/// directions: if either end is boxed, both read boxed. Copies form an
/// undirected union-find; a component stays "unboxed" only when every member
/// has all-`Char` writes and no escaping read.
///
/// Reads verified against kotlinc bytecode as non-escaping (value may stay
/// primitive):
///   `v.compareTo(x)` / `v?.compareTo(x)` / `v!!.compareTo(x)` receivers,
///   `v == x` / `v != x` / `v < x` / `v <= x` / `v > x` / `v >= x` operands,
///   `v is T` / `v as T` subjects, `when (v)` subjects, dead statement reads,
///   the source side of a local-to-local copy.
/// Everything else escapes, notably `===`/`!==`, call arguments, `println(v)`,
/// other member receivers (`v.hashCode()`, `v.toString()`), string templates,
/// `in`/`!in`, `?:`, `v = x` with a non-`Char` right-hand side, and any read
/// inside a nested lambda / local function / object literal / local nominal
/// member body (capture = escape, verified: boxed on both sides).
///
/// Result is consumed by `tryLowerComparableCharCompareTo` in CallLowerer,
/// which swaps the `__kk_comparable_compareTo` (raw diff) dispatch of
/// `v.compareTo(other)` for `kk_char_compareTo` (normalized) when `v` is in
/// the returned set. Storage lowering is untouched — the local stays boxed —
/// `kk_char_compareTo` unboxes either representation.
final class ComparableCharEscapeAnalyzer {
    private let ast: ASTModule
    private let symbols: SymbolTable
    private let types: TypeSystem
    private let bindings: BindingTable
    private let compareToName: InternedString

    /// All `Comparable<Char>` locals discovered, and the nesting depth at
    /// which each was declared.
    private var candidates: Set<SymbolID> = []
    private var candidateDepth: [SymbolID: Int] = [:]
    /// Symbols read in (or copied into a component read in) an object position.
    private var escaped: Set<SymbolID> = []
    /// Symbols written at least once with a value that is neither statically
    /// `Char` nor a copy of another candidate.
    private var nonCharWritten: Set<SymbolID> = []
    /// Copy-edge union-find parent.
    private var unionParent: [SymbolID: SymbolID] = [:]

    init(ast: ASTModule, symbols: SymbolTable, types: TypeSystem, bindings: BindingTable, interner: StringInterner) {
        self.ast = ast
        self.symbols = symbols
        self.types = types
        self.bindings = bindings
        self.compareToName = interner.intern("compareTo")
    }

    /// Returns the `SymbolID`s of `Comparable<Char>` locals whose `compareTo`
    /// receiver read may keep unboxed (normalized) comparison semantics.
    func analyze() -> Set<SymbolID> {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                collectDecl(declID, depth: 0)
            }
        }
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                classifyDecl(declID, depth: 0)
            }
        }
        var result: Set<SymbolID> = []
        for symbol in candidates where componentIsUnboxed(symbol) {
            result.insert(symbol)
        }
        return result
    }

    // MARK: - candidate predicates

    private func isComparableCharType(_ type: TypeID?) -> Bool {
        guard let type,
              let comparableSymbol = types.comparableInterfaceSymbol,
              case let .classType(classType) = types.kind(of: type),
              classType.classSymbol == comparableSymbol,
              classType.args.count == 1,
              let argType = typeArgType(classType.args[0]),
              argType == types.charType
        else {
            return false
        }
        return true
    }

    private func typeArgType(_ arg: TypeArg) -> TypeID? {
        switch arg {
        case let .invariant(type), let .out(type), let .in(type):
            return type
        case .star:
            return nil
        }
    }

    private func isCharValue(_ exprID: ExprID) -> Bool {
        bindings.exprTypes[exprID] == types.charType
    }

    /// The candidate symbol a `nameRef`/`nullAssert(nameRef)` reads, if any.
    private func candidateRead(_ exprID: ExprID, allowNullAssert: Bool = false) -> SymbolID? {
        var current = exprID
        if allowNullAssert, case let .nullAssert(inner, _) = ast.arena.expr(current) {
            current = inner
        }
        guard case .nameRef = ast.arena.expr(current),
              let symbol = bindings.identifierSymbols[current],
              candidates.contains(symbol)
        else {
            return nil
        }
        return symbol
    }

    // MARK: - union-find over copy edges

    private func unionFind(_ symbol: SymbolID) -> SymbolID {
        var current = symbol
        while let parent = unionParent[current], parent != current {
            current = parent
        }
        return current
    }

    private func unionCopy(_ lhs: SymbolID, _ rhs: SymbolID) {
        unionParent[unionFind(rhs)] = unionFind(lhs)
    }

    private func componentIsUnboxed(_ symbol: SymbolID) -> Bool {
        let root = unionFind(symbol)
        for member in candidates where unionFind(member) == root {
            if escaped.contains(member) || nonCharWritten.contains(member) {
                return false
            }
        }
        return true
    }

    // MARK: - structural traversal (shared by the collect and classify passes)

    /// Each direct child expression of `exprID`, with the depth delta and
    /// whether the child sits in a discarded-value statement position.
    private func eachChildExpr(
        of exprID: ExprID,
        depth: Int,
        _ visit: @escaping (ExprID, Int, Bool) -> Void
    ) {
        guard let expr = ast.arena.expr(exprID) else {
            return
        }
        let eachBody: (FunctionBody, Int) -> Void = { body, bodyDepth in
            switch body {
            case let .block(exprs, _):
                for e in exprs { visit(e, bodyDepth, true) }
            case let .expr(e, _):
                visit(e, bodyDepth, false)
            case .unit:
                break
            }
        }
        switch expr {
        case let .localDecl(_, _, _, initializer, _, _):
            if let initializer { visit(initializer, depth, false) }
        case let .localAssign(_, value, _):
            visit(value, depth, false)
        case let .memberAssign(receiver, _, value, _):
            visit(receiver, depth, false)
            visit(value, depth, false)
        case let .indexedAssign(receiver, indices, value, _):
            visit(receiver, depth, false)
            for index in indices { visit(index, depth, false) }
            visit(value, depth, false)
        case let .call(callee, _, args, _):
            visit(callee, depth, false)
            for arg in args { visit(arg.expr, depth, false) }
        case let .memberCall(receiver, _, _, args, _),
             let .safeMemberCall(receiver, _, _, args, _):
            visit(receiver, depth, false)
            for arg in args { visit(arg.expr, depth, false) }
        case let .indexedAccess(receiver, indices, _):
            visit(receiver, depth, false)
            for index in indices { visit(index, depth, false) }
        case let .binary(_, lhs, rhs, _):
            visit(lhs, depth, false)
            visit(rhs, depth, false)
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject { visit(subject, depth, false) }
            for branch in branches {
                for condition in branch.conditions { visit(condition, depth, false) }
                if let guardExpr = branch.guard_ { visit(guardExpr, depth, false) }
                visit(branch.body, depth, false)
            }
            if let elseExpr { visit(elseExpr, depth, false) }
        case let .returnExpr(value, _, _):
            if let value { visit(value, depth, false) }
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            visit(condition, depth, false)
            visit(thenExpr, depth, false)
            if let elseExpr { visit(elseExpr, depth, false) }
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            visit(body, depth, false)
            for clause in catchClauses { visit(clause.body, depth, false) }
            if let finallyExpr { visit(finallyExpr, depth, false) }
        case let .unaryExpr(_, operand, _):
            visit(operand, depth, false)
        case let .isCheck(subject, _, _, _), let .asCast(subject, _, _, _):
            visit(subject, depth, false)
        case let .nullAssert(inner, _):
            visit(inner, depth, false)
        case let .compoundAssign(_, _, value, _):
            visit(value, depth, false)
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            visit(receiver, depth, false)
            for index in indices { visit(index, depth, false) }
            visit(value, depth, false)
        case let .memberCompoundAssign(_, receiver, _, value, _):
            visit(receiver, depth, false)
            visit(value, depth, false)
        case let .throwExpr(value, _):
            visit(value, depth, false)
        case let .lambdaLiteral(_, body, _, _):
            visit(body, depth + 1, false)
        case let .localFunDecl(_, _, valueParams, _, body, _, _):
            for param in valueParams {
                if let defaultValue = param.defaultValue { visit(defaultValue, depth + 1, false) }
            }
            eachBody(body, depth + 1)
        case let .callableRef(receiver, _, _):
            if let receiver { visit(receiver, depth, false) }
        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements { visit(statement, depth, true) }
            if let trailingExpr { visit(trailingExpr, depth, false) }
        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(partExpr) = part { visit(partExpr, depth, false) }
            }
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            visit(lhs, depth, false)
            visit(rhs, depth, false)
        case let .destructuringDecl(_, _, initializer, _):
            visit(initializer, depth, false)
        case let .forExpr(_, iterable, body, _, _):
            visit(iterable, depth, false)
            visit(body, depth, false)
        case let .forDestructuringExpr(_, iterable, body, _):
            visit(iterable, depth, false)
            visit(body, depth, false)
        case let .whileExpr(condition, body, _, _):
            visit(condition, depth, false)
            visit(body, depth, false)
        case let .doWhileExpr(body, condition, _, _):
            visit(body, depth, false)
            visit(condition, depth, false)
        case let .objectLiteral(_, declID, _):
            // Superclass ctor args are evaluated where the literal sits
            // (enclosing frame); the members' bodies are a nested frame.
            guard let declID, let decl = ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl
            else { break }
            for arg in objectDecl.superTypeConstructorArgs {
                visit(arg.expr, depth, false)
            }
            for entry in objectDecl.superTypeEntries {
                if let delegateExpression = entry.delegateExpression {
                    visit(delegateExpression, depth, false)
                }
                for arg in entry.constructorArgs {
                    visit(arg.expr, depth, false)
                }
            }
            for initBlock in objectDecl.initBlocks {
                eachBody(initBlock, depth + 1)
            }
            for member in objectDecl.memberFunctions + objectDecl.memberProperties {
                eachDeclChild(of: member, depth: depth + 1, visit)
            }
            eachNestedNominal(of: objectDecl, depth: depth + 1, visit)
        case let .localNominalDecl(declID, _):
            eachDeclChild(of: declID, depth: depth + 1, visit)
        case .nullLiteral, .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral,
             .doubleLiteral, .charLiteral, .boolLiteral, .stringLiteral, .nameRef,
             .breakExpr, .continueExpr, .superRef, .thisRef:
            break
        }
    }

    /// Member bodies / ctor-arg exprs / nested decls of a nominal decl at the
    /// given inner depth — shared for `objectDecl`, `classDecl`,
    /// `interfaceDecl`, and `enumEntryDecl` wherever they appear.
    private func eachDeclChild(of declID: DeclID, depth: Int, _ visit: @escaping (ExprID, Int, Bool) -> Void) {
        guard let decl = ast.arena.decl(declID) else {
            return
        }
        let eachBody: (FunctionBody) -> Void = { body in
            switch body {
            case let .block(exprs, _):
                for e in exprs { visit(e, depth, true) }
            case let .expr(e, _):
                visit(e, depth, false)
            case .unit:
                break
            }
        }
        let eachProperty: (PropertyDecl) -> Void = { property in
            if let initializer = property.initializer { visit(initializer, depth, false) }
            if let delegateExpression = property.delegateExpression { visit(delegateExpression, depth, false) }
            if let backingField = property.explicitBackingField { visit(backingField.initializer, depth, false) }
            if let getter = property.getter { eachBody(getter.body) }
            if let setter = property.setter { eachBody(setter.body) }
            if let delegateBody = property.delegateBody { eachBody(delegateBody) }
        }
        let eachFun: (FunDecl) -> Void = { fun in
            for param in fun.valueParams {
                if let defaultValue = param.defaultValue { visit(defaultValue, depth, false) }
            }
            eachBody(fun.body)
        }
        let eachCtor: (ConstructorDecl) -> Void = { ctor in
            for param in ctor.valueParams {
                if let defaultValue = param.defaultValue { visit(defaultValue, depth, false) }
            }
            if let delegationCall = ctor.delegationCall {
                for arg in delegationCall.args { visit(arg.expr, depth, false) }
            }
            eachBody(ctor.body)
        }
        switch decl {
        case let .funDecl(fun):
            eachFun(fun)
        case let .propertyDecl(property):
            eachProperty(property)
        case let .classDecl(classDecl):
            for param in classDecl.primaryConstructorParams {
                if let defaultValue = param.defaultValue { visit(defaultValue, depth, false) }
            }
            for entry in classDecl.superTypeEntries {
                if let delegateExpression = entry.delegateExpression { visit(delegateExpression, depth, false) }
                for arg in entry.constructorArgs { visit(arg.expr, depth, false) }
            }
            for initBlock in classDecl.initBlocks { eachBody(initBlock) }
            for ctor in classDecl.secondaryConstructors { eachCtor(ctor) }
            for entry in classDecl.enumEntries {
                for arg in entry.constructorArgs { visit(arg.expr, depth, false) }
                for member in entry.memberFunctions {
                    eachDeclChild(of: member, depth: depth, visit)
                }
            }
            eachNestedNominal(
                memberFunctions: classDecl.memberFunctions,
                memberProperties: classDecl.memberProperties,
                nestedClasses: classDecl.nestedClasses,
                nestedObjects: classDecl.nestedObjects,
                companion: classDecl.companionObject,
                depth: depth,
                visit
            )
        case let .objectDecl(objectDecl):
            for arg in objectDecl.superTypeConstructorArgs { visit(arg.expr, depth, false) }
            for entry in objectDecl.superTypeEntries {
                if let delegateExpression = entry.delegateExpression { visit(delegateExpression, depth, false) }
                for arg in entry.constructorArgs { visit(arg.expr, depth, false) }
            }
            for initBlock in objectDecl.initBlocks { eachBody(initBlock) }
            eachNestedNominal(
                memberFunctions: objectDecl.memberFunctions,
                memberProperties: objectDecl.memberProperties,
                nestedClasses: objectDecl.nestedClasses,
                nestedObjects: objectDecl.nestedObjects,
                companion: nil,
                depth: depth,
                visit
            )
        case let .interfaceDecl(interfaceDecl):
            eachNestedNominal(
                memberFunctions: interfaceDecl.memberFunctions,
                memberProperties: interfaceDecl.memberProperties,
                nestedClasses: interfaceDecl.nestedClasses,
                nestedObjects: interfaceDecl.nestedObjects,
                companion: interfaceDecl.companionObject,
                depth: depth,
                visit
            )
        case let .enumEntryDecl(entry):
            for arg in entry.constructorArgs { visit(arg.expr, depth, false) }
            for member in entry.memberFunctions {
                eachDeclChild(of: member, depth: depth, visit)
            }
        case .typeAliasDecl:
            break
        }
    }

    private func eachNestedNominal(
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        nestedClasses: [DeclID],
        nestedObjects: [DeclID],
        companion: DeclID?,
        depth: Int,
        _ visit: @escaping (ExprID, Int, Bool) -> Void
    ) {
        for member in memberFunctions + memberProperties {
            eachDeclChild(of: member, depth: depth, visit)
        }
        for nested in nestedClasses + nestedObjects {
            eachDeclChild(of: nested, depth: depth, visit)
        }
        if let companion {
            eachDeclChild(of: companion, depth: depth, visit)
        }
    }

    private func eachNestedNominal(of objectDecl: ObjectDecl, depth: Int, _ visit: @escaping (ExprID, Int, Bool) -> Void) {
        eachNestedNominal(
            memberFunctions: [],
            memberProperties: [],
            nestedClasses: objectDecl.nestedClasses,
            nestedObjects: objectDecl.nestedObjects,
            companion: nil,
            depth: depth,
            visit
        )
    }

    // MARK: - pass 1: collect candidates

    private func collectDecl(_ declID: DeclID, depth: Int) {
        eachDeclChild(of: declID, depth: depth + 1) { [self] exprID, exprDepth, _ in
            collectExpr(exprID, depth: exprDepth)
        }
    }

    private func collectExpr(_ exprID: ExprID, depth: Int) {
        if case let .localDecl(_, _, _, _, isDelegated, _) = ast.arena.expr(exprID),
           !isDelegated,
           let symbol = bindings.identifierSymbols[exprID],
           isComparableCharType(symbols.propertyType(for: symbol) ?? bindings.exprTypes[exprID])
        {
            candidates.insert(symbol)
            candidateDepth[symbol] = depth
        }
        eachChildExpr(of: exprID, depth: depth) { [self] child, childDepth, _ in
            collectExpr(child, depth: childDepth)
        }
    }

    // MARK: - pass 2: classify uses

    private func classifyDecl(_ declID: DeclID, depth: Int) {
        eachDeclChild(of: declID, depth: depth + 1) { [self] exprID, exprDepth, isStatement in
            classifyExpr(exprID, depth: exprDepth, statement: isStatement)
        }
    }

    /// Mark `exprID` read in a position that survives unboxed when the read is
    /// in the same frame that declared the candidate.
    private func nonEscapingOperand(_ exprID: ExprID, depth: Int) {
        if let symbol = candidateRead(exprID) {
            if depth > candidateDepth[symbol]! {
                escaped.insert(symbol)
            }
        } else {
            classifyExpr(exprID, depth: depth, statement: false)
        }
    }

    private func classifyCopyTarget(
        sourceSymbol: SymbolID,
        targetExprID: ExprID,
        depth: Int
    ) {
        guard depth <= candidateDepth[sourceSymbol]! else {
            escaped.insert(sourceSymbol)
            return
        }
        guard let target = bindings.identifierSymbols[targetExprID],
              candidates.contains(target)
        else {
            // Stored into a non-candidate slot → the read must materialize a box.
            escaped.insert(sourceSymbol)
            return
        }
        unionCopy(target, sourceSymbol)
    }

    private func classifyExpr(_ exprID: ExprID, depth: Int, statement: Bool) {
        guard let expr = ast.arena.expr(exprID) else {
            return
        }
        switch expr {
        case .nameRef:
            // A leaf read: the default position demands an object; a bare
            // statement read is dead code and stays primitive either way.
            if let symbol = candidateRead(exprID), !statement || depth > candidateDepth[symbol]! {
                escaped.insert(symbol)
            }

        case let .localDecl(_, _, _, initializer, isDelegated, _):
            let symbol = bindings.identifierSymbols[exprID]
            if isDelegated {
                if let initializer { classifyExpr(initializer, depth: depth, statement: false) }
            } else if let initializer {
                if let source = candidateRead(initializer) {
                    classifyCopyTarget(sourceSymbol: source, targetExprID: exprID, depth: depth)
                } else {
                    if let symbol, candidates.contains(symbol), !isCharValue(initializer) {
                        nonCharWritten.insert(symbol)
                    }
                    classifyExpr(initializer, depth: depth, statement: false)
                }
            }

        case let .localAssign(_, value, _):
            let target = bindings.identifierSymbols[exprID]
            if let target, candidates.contains(target) {
                // Write to a candidate: Char RHS keeps provenance, a copy of
                // another candidate merges components, anything else boxes.
                if let source = candidateRead(value) {
                    if depth > candidateDepth[source]! {
                        escaped.insert(source)
                    } else {
                        unionCopy(target, source)
                    }
                } else {
                    if !isCharValue(value) {
                        nonCharWritten.insert(target)
                    }
                    classifyExpr(value, depth: depth, statement: false)
                }
            } else {
                classifyExpr(value, depth: depth, statement: false)
            }

        case let .compoundAssign(_, _, value, _):
            if let symbol = bindings.identifierSymbols[exprID], candidates.contains(symbol) {
                // `v op= x` needs Comparable member dispatch; neither side of
                // the boxing boundary survives.
                escaped.insert(symbol)
                nonCharWritten.insert(symbol)
            }
            classifyExpr(value, depth: depth, statement: false)

        case let .memberCall(receiver, callee, _, args, _),
             let .safeMemberCall(receiver, callee, _, args, _):
            if callee == compareToName, args.count == 1,
               let symbol = candidateRead(receiver, allowNullAssert: true)
            {
                if depth > candidateDepth[symbol]! {
                    escaped.insert(symbol)
                }
                for arg in args {
                    classifyExpr(arg.expr, depth: depth, statement: false)
                }
            } else {
                classifyExpr(receiver, depth: depth, statement: false)
                for arg in args {
                    classifyExpr(arg.expr, depth: depth, statement: false)
                }
            }

        case let .binary(op, lhs, rhs, _):
            switch op {
            case .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                nonEscapingOperand(lhs, depth: depth)
                nonEscapingOperand(rhs, depth: depth)
            default:
                // `===`/`!==` need real references; `?:`, arithmetic and
                // logical operators all consume a produced value.
                classifyExpr(lhs, depth: depth, statement: false)
                classifyExpr(rhs, depth: depth, statement: false)
            }

        case let .isCheck(subject, _, _, _), let .asCast(subject, _, _, _):
            nonEscapingOperand(subject, depth: depth)

        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject {
                nonEscapingOperand(subject, depth: depth)
            }
            for branch in branches {
                for condition in branch.conditions {
                    classifyExpr(condition, depth: depth, statement: false)
                }
                if let guardExpr = branch.guard_ {
                    classifyExpr(guardExpr, depth: depth, statement: false)
                }
                classifyExpr(branch.body, depth: depth, statement: false)
            }
            if let elseExpr {
                classifyExpr(elseExpr, depth: depth, statement: false)
            }

        default:
            eachChildExpr(of: exprID, depth: depth) { [self] child, childDepth, isStatement in
                classifyExpr(child, depth: childDepth, statement: isStatement)
            }
        }
    }
}
