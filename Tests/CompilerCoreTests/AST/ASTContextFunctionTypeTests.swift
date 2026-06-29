#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ASTContextFunctionTypeTests {
    private func buildAST(from source: String) throws -> (ASTModule, CompilationContext) {
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)
        return (try #require(ctx.ast), ctx)
    }

    @Test
    func testBuildASTParsesContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A) (B) -> C
        """
        let (ast, ctx) = try buildAST(from: source)
        let typeAliasDecl = try #require(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try #require(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            Issue.record("Expected function type"); return
        }

        #expect(contextReceivers.count == 1)
        #expect(receiver == nil)
        #expect(params.count == 1)
        #expect(!(isSuspend))
        #expect(!(nullable))
        #expect(renderTypeRef(contextReceivers[0], in: ast, interner: ctx.interner) == "A")
        #expect(renderTypeRef(params[0], in: ast, interner: ctx.interner) == "B")
        #expect(renderTypeRef(returnType, in: ast, interner: ctx.interner) == "C")
    }

    @Test
    func testBuildASTParsesSuspendContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A, B) suspend (C, D) -> E
        """
        let (ast, ctx) = try buildAST(from: source)
        let typeAliasDecl = try #require(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try #require(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            Issue.record("Expected function type"); return
        }

        #expect(contextReceivers.map { renderTypeRef($0, in: ast, interner: ctx.interner) } == ["A", "B"])
        #expect(receiver == nil)
        #expect(params.map { renderTypeRef($0, in: ast, interner: ctx.interner) } == ["C", "D"])
        #expect(renderTypeRef(returnType, in: ast, interner: ctx.interner) == "E")
        #expect(isSuspend)
        #expect(!(nullable))
    }

    @Test
    func testBuildASTParsesContextReceiverFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A) (Receiver) -> R
        """
        let (ast, ctx) = try buildAST(from: source)
        let typeAliasDecl = try #require(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try #require(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            Issue.record("Expected function type"); return
        }

        #expect(contextReceivers.count == 1)
        #expect(renderTypeRef(contextReceivers[0], in: ast, interner: ctx.interner) == "A")
        #expect(receiver == nil)
        #expect(params.count == 1)
        #expect(renderTypeRef(params[0], in: ast, interner: ctx.interner) == "Receiver")
        #expect(renderTypeRef(returnType, in: ast, interner: ctx.interner) == "R")
        #expect(!(isSuspend))
        #expect(!(nullable))
    }

    @Test
    func testBuildASTParsesNestedGenericContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A<B>) (C<D>) -> E
        """
        let (ast, ctx) = try buildAST(from: source)
        let typeAliasDecl = try #require(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try #require(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, _, params, returnType, _, _) = ast.arena.typeRef(underlyingType) else {
            Issue.record("Expected function type"); return
        }

        #expect(renderTypeRef(contextReceivers[0], in: ast, interner: ctx.interner) == "A<B>")
        #expect(renderTypeRef(params[0], in: ast, interner: ctx.interner) == "C<D>")
        #expect(renderTypeRef(returnType, in: ast, interner: ctx.interner) == "E")
    }

    private func renderTypeRef(_ typeRefID: TypeRefID, in ast: ASTModule, interner: StringInterner) -> String {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return "<invalid>"
        }
        switch typeRef {
        case let .named(path, args, nullable):
            let base = path.map(interner.resolve).joined(separator: ".")
            let renderedArgs = if args.isEmpty {
                ""
            } else {
                "<" + args.map { renderTypeArgRef($0, in: ast, interner: interner) }.joined(separator: ", ") + ">"
            }
            return base + renderedArgs + (nullable ? "?" : "")
        case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable):
            let contextPrefix = if contextReceivers.isEmpty {
                ""
            } else {
                "context(" + contextReceivers.map { renderTypeRef($0, in: ast, interner: interner) }.joined(separator: ", ") + ") "
            }
            let suspendPrefix = isSuspend ? "suspend " : ""
            let receiverPrefix = receiver.map { renderTypeRef($0, in: ast, interner: interner) + "." } ?? ""
            let paramsPart = params.map { renderTypeRef($0, in: ast, interner: interner) }.joined(separator: ", ")
            let rendered = contextPrefix + suspendPrefix + receiverPrefix + "(\(paramsPart)) -> " + renderTypeRef(returnType, in: ast, interner: interner)
            return rendered + (nullable ? "?" : "")
        case let .intersection(parts):
            return parts.map { renderTypeRef($0, in: ast, interner: interner) }.joined(separator: " & ")
        case let .annotated(base, annotations):
            let renderedBase = renderTypeRef(base, in: ast, interner: interner)
            if annotations.isEmpty {
                return renderedBase
            } else {
                let renderedAnnotations = annotations.map { "@" + $0.name }.joined(separator: " ")
                return renderedAnnotations + " " + renderedBase
            }
        }
    }

    private func renderTypeArgRef(_ typeArgRef: TypeArgRef, in ast: ASTModule, interner: StringInterner) -> String {
        switch typeArgRef {
        case let .invariant(typeRefID):
            renderTypeRef(typeRefID, in: ast, interner: interner)
        case let .out(typeRefID):
            "out " + renderTypeRef(typeRefID, in: ast, interner: interner)
        case let .in(typeRefID):
            "in " + renderTypeRef(typeRefID, in: ast, interner: interner)
        case .star:
            "*"
        }
    }
}
#endif
