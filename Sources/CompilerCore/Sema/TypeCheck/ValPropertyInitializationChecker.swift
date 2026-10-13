/// Checks immutable field writes after receiver and constructor overload binding.
/// Each path carries the union of fields that may already have been initialized;
/// mutually exclusive branches start from independent snapshots.
final class ValPropertyInitializationChecker {
    private enum Exit: Hashable {
        case normal, returned, thrown
        case broken(InternedString?), continued(InternedString?)
    }
    private struct Flow {
        var paths: [Exit: Set<SymbolID>] = [:]

        init(_ initialized: Set<SymbolID>? = []) {
            paths[.normal] = initialized
        }

        mutating func merge(_ other: Flow) {
            for (exit, initialized) in other.paths {
                paths[exit, default: []].formUnion(initialized)
            }
        }

        mutating func exit(_ exit: Exit) {
            guard let initialized = paths.removeValue(forKey: .normal) else { return }
            paths[exit, default: []].formUnion(initialized)
        }
    }

    private let ast: ASTModule
    private let sema: SemaModule
    private let declarationValidator: DeclarationPositionValidator
    private var owner: SymbolID?
    private var fields: Set<SymbolID> = []
    private var reportedWrites: Set<ExprID> = []

    init(ast: ASTModule, sema: SemaModule, interner: StringInterner) {
        self.ast = ast
        self.sema = sema
        declarationValidator = DeclarationPositionValidator(astArena: ast.arena, interner: interner, diagnostics: nil)
    }

    func check() {
        // DataFlow creates a fresh binding table for the active files. Include
        // local classes and object literals added lazily during inference, which
        // are not in the AST's pre-inference active declaration snapshot.
        for declID in sema.bindings.declSymbols.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let symbol = sema.bindings.declSymbol(for: declID) else { continue }
            switch ast.arena.decl(declID) {
            case let .classDecl(decl):
                checkOwner(symbol, properties: decl.memberProperties, blocks: decl.initBlocks,
                           order: decl.classBodyInitOrder, constructors: decl.secondaryConstructors,
                           parameters: decl.primaryConstructorParams)
            case let .objectDecl(decl):
                checkOwner(symbol, properties: decl.memberProperties, blocks: decl.initBlocks,
                           order: decl.classBodyInitOrder, constructors: [])
            default:
                break
            }
        }
    }

    private func checkOwner(
        _ symbol: SymbolID, properties: [DeclID], blocks: [FunctionBody],
        order: [ClassBodyInitMember], constructors: [ConstructorDecl], parameters: [ValueParamDecl] = []
    ) {
        owner = symbol
        fields = Set(sema.symbols.children(of: symbol).filter {
            guard let field = sema.symbols.symbol($0) else { return false }
            return field.kind == .property && !field.flags.contains(.mutable)
        })
        guard !fields.isEmpty else { return }
        let declaredFields = Set(properties.compactMap { sema.bindings.declSymbol(for: $0) })
        // Primary constructor property parameters have already been initialized.
        let parameterNames = Set(parameters.filter(\.isProperty).map(\.name))
        let parameterFields = fields.filter { field in
            sema.symbols.symbol(field).map { parameterNames.contains($0.name) } ?? false
        }
        var initial = Flow(fields.subtracting(declaredFields).union(parameterFields))
        let order = order.isEmpty
            ? properties.indices.map(ClassBodyInitMember.property) + blocks.indices.map(ClassBodyInitMember.initBlock)
            : order
        for member in order {
            switch member {
            case let .property(index):
                guard properties.indices.contains(index),
                      case let .propertyDecl(property) = ast.arena.decl(properties[index]),
                      let field = sema.bindings.declSymbol(for: properties[index])
                else { continue }
                if let initializer = property.initializer { walk(initializer, flow: &initial) }
                if let delegate = property.delegateExpression { walk(delegate, flow: &initial) }
                let backingField = sema.symbols.backingFieldSymbol(for: field) ?? field
                let computed = declarationValidator.accessorHasBody(property.getter)
                    && !declarationValidator.accessorUsesBackingField(property.getter, isBackingFieldReference: {
                        self.sema.bindings.identifierSymbol(for: $0) == backingField
                    })
                if property.initializer != nil || property.delegateExpression != nil || computed,
                   fields.contains(field), initial.paths[.normal] != nil {
                    initial.paths[.normal, default: []].insert(field)
                }
            case let .initBlock(index):
                guard blocks.indices.contains(index) else { continue }
                walk(blocks[index], flow: &initial)
            }
        }

        let constructorsBySymbol = Dictionary(uniqueKeysWithValues: constructors.compactMap { ctor in
            constructorSymbol(ctor).map { ($0, ctor) }
        })
        var summaries: [SymbolID: Flow] = [:]
        var visiting: Set<SymbolID> = []
        func summary(_ symbol: SymbolID) -> Flow {
            if let cached = summaries[symbol] { return cached }
            // Do not recursively expand a cyclic delegation graph.
            guard visiting.insert(symbol).inserted, let ctor = constructorsBySymbol[symbol] else { return initial }
            var flow = initial
            if ctor.delegationCall?.kind == .this,
               let target = sema.bindings.constructorDelegationCallBinding(for: symbol)?.chosenCallee {
                flow = summary(target)
            }
            walk(ctor.body, flow: &flow)
            // A bare return completes this constructor and resumes its caller.
            if let returned = flow.paths.removeValue(forKey: .returned) {
                flow.paths[.normal, default: []].formUnion(returned)
            }
            summaries[symbol] = flow
            visiting.remove(symbol)
            return flow
        }
        for ctor in constructors {
            if let symbol = constructorSymbol(ctor) { _ = summary(symbol) }
        }
    }

    private func constructorSymbol(_ ctor: ConstructorDecl) -> SymbolID? {
        sema.symbols.symbols(atDeclSite: ctor.range).first {
            sema.symbols.symbol($0)?.kind == .constructor && sema.symbols.parentSymbol(for: $0) == owner
        }
    }

    private func walk(_ body: FunctionBody, flow: inout Flow, permitsInitialization: Bool = true) {
        switch body {
        case .unit: break
        case let .expr(expr, _): walk(expr, flow: &flow, permitsInitialization: permitsInitialization)
        case let .block(exprs, _):
            for expr in exprs { walk(expr, flow: &flow, permitsInitialization: permitsInitialization) }
        }
    }

    private func write(_ id: ExprID, receiver: ExprID?, flow: inout Flow, permitsInitialization: Bool) {
        guard let field = sema.bindings.identifierSymbol(for: id), fields.contains(field),
              let initialized = flow.paths[.normal] else { return }
        let ownReceiver: Bool
        if let receiver {
            if case .thisRef = ast.arena.expr(receiver),
               let type = sema.bindings.exprType(for: receiver),
               case let .classType(classType) = sema.types.kind(of: type) {
                ownReceiver = classType.classSymbol == owner
            } else {
                ownReceiver = false
            }
        } else {
            ownReceiver = true
        }
        let range = ast.arena.exprRange(id)
        let beforeDeclaration = sema.symbols.symbol(field)?.declSite.map { declaration in
            range.map { $0.start.file == declaration.start.file && $0.start.offset < declaration.start.offset } ?? false
        } ?? false
        if !permitsInitialization || !ownReceiver || initialized.contains(field) || beforeDeclaration {
            if reportedWrites.insert(id).inserted {
                let message = beforeDeclaration ? "Variable cannot be initialized before declaration." : "Val cannot be reassigned."
                sema.diagnostics.error("KSWIFTK-SEMA-0014", message, range: range)
            }
        }
        flow.paths[.normal, default: []].insert(field)
    }

    private func walk(_ id: ExprID, flow: inout Flow, permitsInitialization: Bool = true) {
        guard let expr = ast.arena.expr(id) else { return }
        guard let entry = flow.paths[.normal] else {
            // Kotlin still checks writes following return/throw, without letting
            // unreachable statements change the states reaching other branches.
            if flow.paths[.returned] != nil || flow.paths[.thrown] != nil {
                var unreachable = Flow((flow.paths[.returned] ?? []).union(flow.paths[.thrown] ?? []))
                walk(id, flow: &unreachable, permitsInitialization: permitsInitialization)
            }
            return
        }
        func visit(_ child: ExprID) { walk(child, flow: &flow, permitsInitialization: permitsInitialization) }
        func branch(_ child: ExprID?, from entry: Set<SymbolID>) -> Flow {
            var result = Flow(entry)
            if let child { walk(child, flow: &result, permitsInitialization: permitsInitialization) }
            return result
        }
        switch expr {
        case let .localAssign(_, value, _):
            visit(value)
            write(id, receiver: nil, flow: &flow, permitsInitialization: permitsInitialization)
        case let .memberAssign(receiver, _, value, _):
            visit(receiver); visit(value)
            write(id, receiver: receiver, flow: &flow, permitsInitialization: permitsInitialization)
        case let .blockExpr(statements, trailing, _):
            for statement in statements { visit(statement) }
            if let trailing { visit(trailing) }
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            visit(condition)
            if let entry = flow.paths.removeValue(forKey: .normal) {
                flow.merge(branch(thenExpr, from: entry))
                flow.merge(branch(elseExpr, from: entry))
            }
        case let .whenExpr(subject, branches, elseExpr, _):
            if let subject { visit(subject) }
            if let entry = flow.paths.removeValue(forKey: .normal) {
                var remaining = Flow(entry)
                for arm in branches {
                    // Conditions can execute even when their arm is not selected.
                    for condition in arm.conditions { walk(condition, flow: &remaining, permitsInitialization: permitsInitialization) }
                    if let guardExpr = arm.guard_ { walk(guardExpr, flow: &remaining, permitsInitialization: permitsInitialization) }
                    if let armEntry = remaining.paths[.normal] { flow.merge(branch(arm.body, from: armEntry)) }
                }
                if let elseExpr { flow.merge(branch(elseExpr, from: remaining.paths[.normal] ?? entry)) }
                else if sema.bindings.whenExhaustiveness[id] != true { flow.merge(remaining) }
            }
        case let .returnExpr(value, _, _):
            if let value { visit(value) }
            flow.exit(.returned)
        case let .throwExpr(value, _):
            visit(value); flow.exit(.thrown)
        case let .breakExpr(label, _): flow.exit(.broken(label))
        case let .continueExpr(label, _): flow.exit(.continued(label))
        case let .whileExpr(condition, body, label, _):
            visit(condition)
            walkLoop(body: body, condition: condition, label: label, atLeastOnce: false, flow: &flow, permitsInitialization: permitsInitialization)
        case let .doWhileExpr(body, condition, label, _):
            walkLoop(body: body, condition: condition, label: label, atLeastOnce: true, flow: &flow, permitsInitialization: permitsInitialization)
        case let .forExpr(_, iterable, body, label, _):
            visit(iterable)
            walkLoop(body: body, condition: nil, label: label, atLeastOnce: false, flow: &flow, permitsInitialization: permitsInitialization)
        case let .forDestructuringExpr(_, iterable, body, _):
            visit(iterable)
            walkLoop(body: body, condition: nil, label: nil, atLeastOnce: false, flow: &flow, permitsInitialization: permitsInitialization)
        case let .tryExpr(body, catches, finallyExpr, _):
            var attempted = branch(body, from: entry)
            let catchEntry = attempted.paths.values.reduce(entry) { $0.union($1) }
            for clause in catches { attempted.merge(branch(clause.body, from: catchEntry)) }
            flow.paths[.normal] = nil
            if let finallyExpr {
                var completed = Flow(nil)
                var cleanups: [Set<SymbolID>: Flow] = [:]
                for (exit, state) in attempted.paths {
                    let checked = cleanups[state] ?? branch(finallyExpr, from: state)
                    cleanups[state] = checked
                    var cleanup = checked
                    if let normal = cleanup.paths.removeValue(forKey: .normal) {
                        cleanup.paths[exit, default: []].formUnion(normal)
                    }
                    completed.merge(cleanup)
                }
                flow.merge(completed)
            } else { flow.merge(attempted) }
        case let .binary(op, lhs, rhs, _):
            visit(lhs)
            if op == .logicalAnd || op == .logicalOr || op == .elvis {
                if let entry = flow.paths[.normal] { flow.merge(branch(rhs, from: entry)) }
            } else { visit(rhs) }
        case let .call(callee, _, args, _), let .memberCall(callee, _, _, args, _):
            visit(callee)
            visitArguments(args, flow: &flow, permitsInitialization: permitsInitialization)
        case let .safeMemberCall(receiver, _, _, args, _):
            visit(receiver)
            var called = flow
            visitArguments(args, flow: &called, permitsInitialization: permitsInitialization)
            flow.merge(called)
        case let .lambdaLiteral(_, body, _, _):
            var deferred = Flow(entry)
            walk(body, flow: &deferred, permitsInitialization: false)
        case let .localFunDecl(_, _, _, _, body, _, _, _):
            var deferred = Flow(entry)
            walk(body, flow: &deferred, permitsInitialization: false)
        case let .localDecl(_, _, _, initializer, _, _, _):
            if let initializer { visit(initializer) }
        case let .destructuringDecl(_, _, initializer, _): visit(initializer)
        case let .indexedAccess(receiver, indices, _):
            visit(receiver); for index in indices { visit(index) }
        case let .indexedAssign(receiver, indices, value, _), let .indexedCompoundAssign(_, receiver, indices, value, _):
            visit(receiver); for index in indices { visit(index) }; visit(value)
        case let .compoundAssign(_, _, value, _): visit(value)
        case let .memberCompoundAssign(_, receiver, _, value, _): visit(receiver); visit(value)
        case let .unaryExpr(_, operand, _), let .isCheck(operand, _, _, _),
             let .asCast(operand, _, _, _), let .nullAssert(operand, _): visit(operand)
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _): visit(lhs); visit(rhs)
        case let .callableRef(receiver, _, _): if let receiver { visit(receiver) }
        case let .stringTemplate(parts, _):
            for part in parts { if case let .expression(child) = part { visit(child) } }
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral,
             .charLiteral, .nullLiteral, .boolLiteral, .stringLiteral, .nameRef, .superRef, .thisRef,
             .objectLiteral, .localNominalDecl:
            break
        }
        if sema.bindings.exprType(for: id) == sema.types.nothingType { flow.exit(.thrown) }
    }

    private func walkLoop(body: ExprID, condition: ExprID?, label: InternedString?, atLeastOnce: Bool, flow: inout Flow, permitsInitialization: Bool) {
        guard let entry = flow.paths.removeValue(forKey: .normal) else { return }
        let constantCondition: Bool? = condition.flatMap {
            if case let .boolLiteral(value, _) = ast.arena.expr($0) { return value }
            return nil
        }
        if !atLeastOnce, constantCondition == false {
            var unreachable = Flow(entry)
            walk(body, flow: &unreachable, permitsInitialization: permitsInitialization)
            flow.paths[.normal] = entry
            return
        }
        var iteration = Flow(entry)
        walk(body, flow: &iteration, permitsInitialization: permitsInitialization)
        let matchingLabels: Set<InternedString?> = [nil, label]
        for label in matchingLabels {
            if let continued = iteration.paths.removeValue(forKey: .continued(label)) {
                iteration.paths[.normal, default: []].formUnion(continued)
            }
        }
        if let condition { walk(condition, flow: &iteration, permitsInitialization: permitsInitialization) }
        if constantCondition != false, let backEdge = iteration.paths[.normal], backEdge != entry {
            var repeated = Flow(backEdge)
            walk(body, flow: &repeated, permitsInitialization: permitsInitialization)
            iteration.merge(repeated)
        }
        // A constant-true loop completes only through a matching break.
        if constantCondition == true { iteration.paths[.normal] = nil }
        for label in matchingLabels {
            if let broken = iteration.paths.removeValue(forKey: .broken(label)) {
                iteration.paths[.normal, default: []].formUnion(broken)
            }
            iteration.paths[.continued(label)] = nil
        }
        if !atLeastOnce, constantCondition != true { iteration.paths[.normal, default: []].formUnion(entry) }
        flow.merge(iteration)
    }

    private func visitArguments(_ args: [CallArgument], flow: inout Flow, permitsInitialization: Bool) {
        for argument in args {
            walk(argument.expr, flow: &flow, permitsInitialization: permitsInitialization)
        }
    }
}
