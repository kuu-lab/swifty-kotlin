/// Proves effective immutability before flow inference, including deferred writes
/// in closures. A local with any reassignment is conservatively excluded.
final class LocalVariableStabilityAnalyzer {
    private var analyzedRoots: Set<ExprID> = []
    private var declarations: Set<ExprID> = []
    private var reassigned: Set<ExprID> = []

    func isNeverReassigned(_ declaration: ExprID) -> Bool {
        declarations.contains(declaration) && !reassigned.contains(declaration)
    }

    func analyze(_ body: FunctionBody, ast: ASTModule) {
        let roots: [ExprID] = switch body {
        case let .block(expressions, _): expressions
        case let .expr(expression, _): [expression]
        case .unit: []
        }
        analyze(roots, ast: ast)
    }

    func analyze(_ roots: [ExprID], ast: ASTModule) {
        guard roots.contains(where: { !analyzedRoots.contains($0) }) else { return }
        var locals: [InternedString: ExprID] = [:]
        for root in roots {
            visit(root, ast: ast, locals: &locals)
            analyzedRoots.insert(root)
        }
    }

    private func visitBody(_ body: FunctionBody, ast: ASTModule, locals: [InternedString: ExprID]) {
        var scope = locals
        switch body {
        case let .block(expressions, _):
            for expression in expressions { visit(expression, ast: ast, locals: &scope) }
        case let .expr(expression, _):
            visit(expression, ast: ast, locals: &scope)
        case .unit: break
        }
    }

    private func visit(_ id: ExprID, ast: ASTModule, locals: inout [InternedString: ExprID]) {
        guard let expression = ast.arena.expr(id) else { return }
        func scoped(_ child: ExprID, hiding names: [InternedString] = []) {
            var scope = locals
            for name in names { scope.removeValue(forKey: name) }
            visit(child, ast: ast, locals: &scope)
        }
        func children(_ expressions: [ExprID]) {
            for expression in expressions { visit(expression, ast: ast, locals: &locals) }
        }
        switch expression {
        case let .localDecl(name, _, _, initializer, _, _):
            if let initializer { children([initializer]) }
            declarations.insert(id)
            locals[name] = id
        case let .destructuringDecl(names, _, initializer, _):
            children([initializer])
            declarations.insert(id)
            for name in names.compactMap({ $0 }) { locals[name] = id }
        case let .localAssign(name, value, _), let .compoundAssign(_, name, value, _):
            if let declaration = locals[name] { reassigned.insert(declaration) }
            children([value])
        case let .blockExpr(statements, trailing, _):
            var scope = locals
            for child in statements + (trailing.map { [$0] } ?? []) {
                visit(child, ast: ast, locals: &scope)
            }
        case let .lambdaLiteral(params, body, _, _):
            scoped(body, hiding: params)
        case let .localFunDecl(name, params, _, body, _, _):
            var scope = locals
            for param in params {
                scope.removeValue(forKey: param.name)
                if let value = param.defaultValue { scoped(value) }
            }
            scope.removeValue(forKey: name)
            visitBody(body, ast: ast, locals: scope)
            locals.removeValue(forKey: name)
        case let .forExpr(variable, iterable, body, _, _):
            children([iterable])
            scoped(body, hiding: variable.map { [$0] } ?? [])
        case let .forDestructuringExpr(names, iterable, body, _):
            children([iterable])
            scoped(body, hiding: names.compactMap { $0 })
        case let .whileExpr(condition, body, _, _):
            children([condition])
            scoped(body)
        case let .doWhileExpr(body, condition, _, _):
            scoped(body)
            scoped(condition)
        case let .ifExpr(condition, thenBody, elseBody, _):
            children([condition])
            scoped(thenBody)
            if let elseBody { scoped(elseBody) }
        case let .whenExpr(subject, branches, elseBody, _):
            var scope = locals
            if let subject { visit(subject, ast: ast, locals: &scope) }
            for branch in branches {
                var branchScope = scope
                for child in branch.conditions + (branch.guard_.map { [$0] } ?? []) + [branch.body] {
                    visit(child, ast: ast, locals: &branchScope)
                }
            }
            if let elseBody { visit(elseBody, ast: ast, locals: &scope) }
        case let .tryExpr(body, catches, finallyBody, _):
            scoped(body)
            for clause in catches { scoped(clause.body, hiding: clause.paramName.map { [$0] } ?? []) }
            if let finallyBody { scoped(finallyBody) }
        case let .call(callee, _, args, _):
            children([callee] + args.map(\.expr))
        case let .memberCall(receiver, _, _, args, _), let .safeMemberCall(receiver, _, _, args, _):
            children([receiver] + args.map(\.expr))
        case let .memberAssign(receiver, _, value, _), let .memberCompoundAssign(_, receiver, _, value, _):
            children([receiver, value])
        case let .indexedAccess(receiver, indices, _):
            children([receiver] + indices)
        case let .indexedAssign(receiver, indices, value, _), let .indexedCompoundAssign(_, receiver, indices, value, _):
            children([receiver] + indices + [value])
        case let .binary(_, lhs, rhs, _), let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            children([lhs, rhs])
        case let .unaryExpr(_, value, _), let .isCheck(value, _, _, _), let .asCast(value, _, _, _),
             let .nullAssert(value, _), let .throwExpr(value, _):
            children([value])
        case let .returnExpr(value, _, _), let .callableRef(value, _, _):
            if let value { children([value]) }
        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(value) = part { children([value]) }
            }
        case let .objectLiteral(_, declaration, _):
            if let declaration { visitNominal(declaration, ast: ast, locals: locals) }
        case let .localNominalDecl(declaration, _):
            visitNominal(declaration, ast: ast, locals: locals)
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral,
             .charLiteral, .boolLiteral, .stringLiteral, .nameRef, .breakExpr, .continueExpr, .superRef, .thisRef:
            break
        }
    }

    private func visitNominal(_ id: DeclID, ast: ASTModule, locals: [InternedString: ExprID]) {
        guard let declaration = ast.arena.decl(id) else { return }
        let functions: [DeclID]
        let properties: [DeclID]
        let initBlocks: [FunctionBody]
        let arguments: [ExprID]
        let nestedDeclarations: [DeclID]
        var scope = locals
        switch declaration {
        case let .classDecl(decl):
            functions = decl.memberFunctions
            properties = decl.memberProperties
            initBlocks = decl.initBlocks + decl.secondaryConstructors.map(\.body)
            arguments = decl.superTypeEntries.flatMap(\.constructorArgs).map(\.expr)
                + decl.superTypeEntries.compactMap(\.delegateExpression)
                + decl.primaryConstructorParams.compactMap(\.defaultValue)
            nestedDeclarations = decl.nestedClasses + decl.nestedObjects
            for param in decl.primaryConstructorParams { scope.removeValue(forKey: param.name) }
        case let .objectDecl(decl):
            functions = decl.memberFunctions
            properties = decl.memberProperties
            initBlocks = decl.initBlocks
            arguments = decl.superTypeConstructorArgs.map(\.expr)
            nestedDeclarations = decl.nestedClasses + decl.nestedObjects
        default: return
        }
        for property in properties {
            if case let .propertyDecl(decl) = ast.arena.decl(property) { scope.removeValue(forKey: decl.name) }
        }
        for argument in arguments { visit(argument, ast: ast, locals: &scope) }
        for function in functions {
            guard case let .funDecl(decl) = ast.arena.decl(function) else { continue }
            var functionScope = scope
            for param in decl.valueParams { functionScope.removeValue(forKey: param.name) }
            visitBody(decl.body, ast: ast, locals: functionScope)
        }
        for property in properties {
            guard case let .propertyDecl(decl) = ast.arena.decl(property) else { continue }
            if let initializer = decl.initializer { visit(initializer, ast: ast, locals: &scope) }
            for body in [decl.getter?.body, decl.setter?.body, decl.delegateBody].compactMap({ $0 }) {
                visitBody(body, ast: ast, locals: scope)
            }
        }
        for body in initBlocks { visitBody(body, ast: ast, locals: scope) }
        for nested in nestedDeclarations { visitNominal(nested, ast: ast, locals: scope) }
    }
}
