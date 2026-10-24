/// Checks field initialization after receiver and constructor overload binding.
/// Paths retain both possible writes (union, for val reassignment) and definite
/// writes (intersection, for initialization on every normal constructor exit).
final class ValPropertyInitializationChecker {
    private enum Exit: Hashable {
        case normal, returned, lambdaReturned, thrown
        case broken(InternedString?), continued(InternedString?)
    }
    private struct State: Hashable {
        var possible: Set<SymbolID>
        var definite: Set<SymbolID>

        init(_ initialized: Set<SymbolID> = []) {
            possible = initialized
            definite = initialized
        }

        mutating func merge(_ other: State) {
            possible.formUnion(other.possible)
            definite.formIntersection(other.definite)
        }

        mutating func insert(_ field: SymbolID) {
            possible.insert(field)
            definite.insert(field)
        }
    }

    private struct Flow {
        var paths: [Exit: State] = [:]

        init(_ initialized: State? = State()) {
            paths[.normal] = initialized
        }

        mutating func merge(_ other: Flow) {
            for (exit, initialized) in other.paths {
                merge(initialized, at: exit)
            }
        }

        mutating func merge(_ state: State, at exit: Exit) {
            if paths[exit] != nil { paths[exit]?.merge(state) }
            else { paths[exit] = state }
        }

        mutating func exit(_ exit: Exit) {
            guard let initialized = paths.removeValue(forKey: .normal) else { return }
            merge(initialized, at: exit)
        }
    }

    private let ast: ASTModule
    private let sema: SemaModule
    private let sourceManager: SourceManager?
    private let declarationValidator: DeclarationPositionValidator
    private var checkingConstructorBody = false
    private var owner: SymbolID?
    private var fields: Set<SymbolID> = []
    private var customSetterFields: Set<SymbolID> = []
    private var immutableFields: Set<SymbolID> = []
    private var reportedMissing: Set<SymbolID> = []
    private var reportedWrites: Set<ExprID> = []
    private var inlineLambdaBodyDepth = 0
    private var deferredLambdaBodyDepth = 0

    init(ast: ASTModule, sema: SemaModule, interner: StringInterner, sourceManager: SourceManager? = nil) {
        self.ast = ast
        self.sema = sema
        self.sourceManager = sourceManager
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
                           parameters: decl.primaryConstructorParams,
                           hasPrimaryConstructor: decl.hasPrimaryConstructorSyntax || decl.secondaryConstructors.isEmpty,
                           checksDefiniteInitialization: !decl.modifiers.contains(.expect) && !decl.modifiers.contains(.annotationClass))
                if sema.symbols.symbol(symbol)?.kind == .enumClass,
                   let enumInfo = sema.symbols.symbol(symbol)
                {
                    for entry in decl.enumEntries where !entry.initBlocks.isEmpty {
                        let entryFQName = enumInfo.fqName + [entry.name]
                        guard let entrySymbol = sema.symbols.lookupAll(fqName: entryFQName).first(where: { candidate in
                            sema.symbols.symbol(candidate)?.kind == .field
                                && sema.symbols.parentSymbol(for: candidate) == symbol
                        }) else {
                            continue
                        }
                        checkOwner(
                            entrySymbol,
                            properties: entry.memberProperties,
                            blocks: entry.initBlocks,
                            order: entry.classBodyInitOrder,
                            constructors: [],
                            checksDefiniteInitialization: !decl.modifiers.contains(.expect)
                        )
                    }
                }
            case let .objectDecl(decl):
                checkOwner(symbol, properties: decl.memberProperties, blocks: decl.initBlocks,
                           order: decl.classBodyInitOrder, constructors: [],
                           checksDefiniteInitialization: !decl.modifiers.contains(.expect))
            default:
                break
            }
        }
    }

    private func checkOwner(
        _ symbol: SymbolID, properties: [DeclID], blocks: [FunctionBody],
        order: [ClassBodyInitMember], constructors: [ConstructorDecl], parameters: [ValueParamDecl] = [],
        hasPrimaryConstructor: Bool = true, checksDefiniteInitialization: Bool = true
    ) {
        owner = symbol
        fields = Set(sema.symbols.children(of: symbol).filter {
            guard let field = sema.symbols.symbol($0) else { return false }
            return field.kind == .property
        })
        guard !fields.isEmpty else { return }
        immutableFields = fields.filter { sema.symbols.symbol($0)?.flags.contains(.mutable) == false }
        customSetterFields = Set(properties.compactMap { id in
            guard case let .propertyDecl(property) = ast.arena.decl(id),
                  declarationValidator.accessorHasBody(property.setter) else { return nil }
            return sema.bindings.declSymbol(for: id)
        })
        // DeclarationPositionValidator handles owners without an initializer
        // flow. Recheck deferred cases here, avoiding duplicate diagnostics.
        let isBundledStdlibOwner: Bool
        if let fileID = sema.symbols.symbol(symbol)?.declSite?.start.file {
            isBundledStdlibOwner = sourceManager?.origin(of: fileID)?.isBundledStdlib == true
        } else {
            isBundledStdlibOwner = false
        }
        let hasPropertyInitializationExpression = !isBundledStdlibOwner && properties.contains { id in
            guard case let .propertyDecl(property) = ast.arena.decl(id) else { return false }
            return property.initializer != nil
                || property.delegateExpression != nil
                || property.explicitBackingField != nil
        }
        let required = checksDefiniteInitialization
            && (!blocks.isEmpty || !constructors.isEmpty || hasPropertyInitializationExpression)
            ? Set(properties.compactMap { id -> SymbolID? in
                guard case let .propertyDecl(property) = ast.arena.decl(id),
                      let field = sema.bindings.declSymbol(for: id),
                      !property.isSynthesizedPrimaryConstructorProperty,
                      !property.modifiers.contains(.abstract), !property.modifiers.contains(.lateinit),
                      !property.modifiers.contains(.expect), !property.modifiers.contains(.const),
                      property.receiverType == nil, property.initializer == nil,
                      property.delegateExpression == nil, property.explicitBackingField == nil,
                      !isFieldless(property, symbol: field)
                else { return nil }
                return field
            }) : []
        let declaredFields = Set(properties.compactMap { sema.bindings.declSymbol(for: $0) })
        // Primary constructor property parameters have already been initialized.
        let parameterNames = Set(parameters.filter(\.isProperty).map(\.name))
        let parameterFields = fields.filter { field in
            sema.symbols.symbol(field).map { parameterNames.contains($0.name) } ?? false
        }
        var initial = Flow(State(fields.subtracting(declaredFields).union(parameterFields)))
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
                if let explicit = property.explicitBackingField { walk(explicit.initializer, flow: &initial) }
                if property.initializer != nil || property.delegateExpression != nil
                    || property.explicitBackingField != nil || isFieldless(property, symbol: field),
                   fields.contains(field), initial.paths[.normal] != nil {
                    initial.paths[.normal]?.insert(field)
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
            // Constructor bodies run after every property declaration/init block,
            // even when a constructor appears earlier in the source text.
            checkingConstructorBody = true
            walk(ctor.body, flow: &flow)
            checkingConstructorBody = false
            // A bare return completes this constructor and resumes its caller.
            if let returned = flow.paths.removeValue(forKey: .returned) {
                flow.merge(returned, at: .normal)
            }
            summaries[symbol] = flow
            visiting.remove(symbol)
            return flow
        }
        // Properties after a class initializer sequence that never reaches a
        // normal exit cannot be observed on a constructed instance. Keep the
        // constructor-body checks below for normally completing initializers:
        // a secondary constructor that itself never returns still follows the
        // existing definite-initialization rule.
        let hasNormalInitializationPath = initial.paths[.normal] != nil
        if hasPrimaryConstructor && hasNormalInitializationPath {
            reportMissing(required, in: initial)
        }
        for ctor in constructors {
            if let symbol = constructorSymbol(ctor) {
                let flow = summary(symbol)
                if hasNormalInitializationPath { reportMissing(required, in: flow) }
            }
        }
    }

    private func isFieldless(_ property: PropertyDecl, symbol: SymbolID) -> Bool {
        let backingField = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
        let usesField = declarationValidator.accessorUsesBackingField(property.getter, isBackingFieldReference: {
            self.sema.bindings.identifierSymbol(for: $0) == backingField
        }) || declarationValidator.accessorUsesBackingField(property.setter, isBackingFieldReference: {
            self.sema.bindings.identifierSymbol(for: $0) == backingField
        })
        return declarationValidator.accessorHasBody(property.getter)
            && (!property.isVar || declarationValidator.accessorHasBody(property.setter)) && !usesField
    }

    private func reportMissing(_ required: Set<SymbolID>, in flow: Flow) {
        let initialized = flow.paths[.normal]?.definite ?? []
        for field in required.subtracting(initialized).sorted(by: { $0.rawValue < $1.rawValue }) {
            guard reportedMissing.insert(field).inserted else { continue }
            sema.diagnostics.error("KSWIFTK-SEMA-0424", "property must be initialized or be abstract.",
                                   range: sema.symbols.symbol(field)?.declSite)
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
        let beforeDeclaration = !checkingConstructorBody && (sema.symbols.symbol(field)?.declSite.map { declaration in
            range.map { $0.start.file == declaration.start.file && $0.start.offset < declaration.start.offset } ?? false
        } ?? false)
        if immutableFields.contains(field),
           !permitsInitialization || !ownReceiver || initialized.possible.contains(field) || beforeDeclaration {
            if reportedWrites.insert(id).inserted {
                let message = beforeDeclaration ? "Variable cannot be initialized before declaration." : "Val cannot be reassigned."
                sema.diagnostics.error("KSWIFTK-SEMA-0014", message, range: range)
            }
        }
        if permitsInitialization && ownReceiver && !beforeDeclaration {
            flow.paths[.normal]?.possible.insert(field)
            // Calling a custom setter does not initialize the backing field.
            if !customSetterFields.contains(field) { flow.paths[.normal]?.definite.insert(field) }
        }
    }

    private func walk(_ id: ExprID, flow: inout Flow, permitsInitialization: Bool = true) {
        guard let expr = ast.arena.expr(id) else { return }
        guard let entry = flow.paths[.normal] else {
            // Kotlin still checks writes following return/throw, without letting
            // unreachable statements change the states reaching other branches.
            if flow.paths[.returned] != nil || flow.paths[.thrown] != nil {
                var state = flow.paths[.returned] ?? flow.paths[.thrown] ?? State()
                if let thrown = flow.paths[.thrown] { state.merge(thrown) }
                var unreachable = Flow(state)
                walk(id, flow: &unreachable, permitsInitialization: permitsInitialization)
            }
            return
        }
        func visit(_ child: ExprID) { walk(child, flow: &flow, permitsInitialization: permitsInitialization) }
        func branch(_ child: ExprID?, from entry: State) -> Flow {
            var result = Flow(entry)
            if let child { walk(child, flow: &result, permitsInitialization: permitsInitialization) }
            return result
        }
        switch expr {
        case let .localAssign(_, value, _):
            visit(value)
            write(id, receiver: nil, flow: &flow, permitsInitialization: permitsInitialization)
        case let .memberAssign(receiver, _, value, _),
             let .safeMemberAssign(receiver, _, value, _):
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
            if inlineLambdaBodyDepth > deferredLambdaBodyDepth {
                if sema.bindings.lambdaReturnTargets[id] != nil {
                    flow.exit(.lambdaReturned)
                } else if sema.bindings.functionReturnLambdaPaths[id] != nil {
                    flow.exit(.returned)
                }
            } else {
                flow.exit(.returned)
            }
        case let .throwExpr(value, _):
            visit(value); flow.exit(.thrown)
        case let .breakExpr(label, _): flow.exit(.broken(label))
        case let .continueExpr(label, _): flow.exit(.continued(label))
        case let .whileExpr(condition, body, label, _):
            visit(condition)
            walkLoop(body: body, condition: condition, label: label, atLeastOnce: false, flow: &flow, permitsInitialization: permitsInitialization)
        case let .doWhileExpr(body, condition, label, _):
            walkLoop(body: body, condition: condition, label: label, atLeastOnce: true, flow: &flow, permitsInitialization: permitsInitialization)
        case let .forExpr(_, _, iterable, body, label, _):
            visit(iterable)
            walkLoop(body: body, condition: nil, label: label, atLeastOnce: false, flow: &flow, permitsInitialization: permitsInitialization)
        case let .forDestructuringExpr(_, iterable, body, _, _):
            visit(iterable)
            walkLoop(body: body, condition: nil, label: ast.arena.loopLabel(for: id), atLeastOnce: false, flow: &flow, permitsInitialization: permitsInitialization)
        case let .tryExpr(body, catches, finallyExpr, _):
            var attempted = branch(body, from: entry)
            // Exceptions may happen before any write in the try body. Preserve
            // possible writes for reassignment, but only entry writes are definite.
            var catchEntry = entry
            for state in attempted.paths.values { catchEntry.possible.formUnion(state.possible) }
            for clause in catches { attempted.merge(branch(clause.body, from: catchEntry)) }
            flow.paths[.normal] = nil
            if let finallyExpr {
                var completed = Flow(nil)
                var cleanups: [State: Flow] = [:]
                for (exit, state) in attempted.paths {
                    let checked = cleanups[state] ?? branch(finallyExpr, from: state)
                    cleanups[state] = checked
                    var cleanup = checked
                    if let normal = cleanup.paths.removeValue(forKey: .normal) {
                        cleanup.merge(normal, at: exit)
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
            visitArguments(args, callExprID: id, flow: &flow, permitsInitialization: permitsInitialization)
        case let .safeMemberCall(receiver, _, _, args, _):
            visit(receiver)
            var called = flow
            visitArguments(args, callExprID: id, flow: &called, permitsInitialization: permitsInitialization)
            flow.merge(called)
        case let .lambdaLiteral(_, body, _, _):
            var deferred = Flow(entry)
            deferredLambdaBodyDepth += 1
            walk(body, flow: &deferred, permitsInitialization: false)
            deferredLambdaBodyDepth -= 1
        case let .localFunDecl(_, _, _, _, body, _, _, _, _):
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
                iteration.merge(continued, at: .normal)
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
                iteration.merge(broken, at: .normal)
            }
            iteration.paths[.continued(label)] = nil
        }
        if !atLeastOnce, constantCondition != true { iteration.merge(entry, at: .normal) }
        flow.merge(iteration)
    }

    private func visitArguments(
        _ args: [CallArgument],
        callExprID: ExprID,
        flow: inout Flow,
        permitsInitialization: Bool
    ) {
        for (argumentIndex, argument) in args.enumerated() {
            guard deferredLambdaBodyDepth == 0,
                  allowsNonLocalReturn(argumentIndex: argumentIndex, callExprID: callExprID),
                  case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(argument.expr),
                  let entry = flow.paths[.normal]
            else {
                walk(argument.expr, flow: &flow, permitsInitialization: permitsInitialization)
                continue
            }

            // An inline callback may exit the constructor from inside its body.
            // Keep that path separate from normal callback completion, since an
            // inline function is not necessarily required to invoke its callback.
            var callback = Flow(entry)
            inlineLambdaBodyDepth += 1
            walk(body, flow: &callback, permitsInitialization: true)
            inlineLambdaBodyDepth -= 1

            if let localReturn = callback.paths.removeValue(forKey: .lambdaReturned) {
                callback.merge(localReturn, at: .normal)
            }
            if let normal = callback.paths[.normal] {
                flow.merge(normal, at: .normal)
            }
            if let returned = callback.paths[.returned] {
                flow.merge(returned, at: .returned)
            }
        }
    }

    private func allowsNonLocalReturn(argumentIndex: Int, callExprID: ExprID) -> Bool {
        guard let binding = sema.bindings.callBinding(for: callExprID),
              sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.inlineFunction) == true,
              let signature = sema.symbols.functionSignature(for: binding.chosenCallee)
        else { return false }
        let parameterIndex = binding.parameterMapping[argumentIndex] ?? argumentIndex
        return !signature.valueParameterAllowsNonLocalReturn.indices.contains(parameterIndex)
            || signature.valueParameterAllowsNonLocalReturn[parameterIndex]
    }
}
