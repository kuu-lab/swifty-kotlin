#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ASTContextFunctionTypeTests {
    /// Compiles a `typealias Handler = <type>` fixture and returns the
    /// rendered underlying type. The rendered form encodes context receivers,
    /// `suspend`, receiver, params, return type, and nullability.
    private func renderedHandlerType(from source: String) throws -> String {
        let (ast, ctx) = try buildASTModule(from: source)
        let typeAliasDecl = try #require(firstTypeAliasDecl(named: "Handler", in: ast, interner: ctx.interner))
        let underlyingType = try #require(typeAliasDecl.underlyingType)
        return renderTypeRef(underlyingType, in: ast, interner: ctx.interner)
    }

    @Test
    func testBuildASTParsesContextFunctionTypeAlias() throws {
        let rendered = try renderedHandlerType(from: """
        package demo
        typealias Handler = context(A) (B) -> C
        """)
        #expect(rendered == "context(A) (B) -> C")
    }

    @Test
    func testBuildASTParsesSuspendContextFunctionTypeAlias() throws {
        let rendered = try renderedHandlerType(from: """
        package demo
        typealias Handler = context(A, B) suspend (C, D) -> E
        """)
        #expect(rendered == "context(A, B) suspend (C, D) -> E")
    }

    @Test
    func testBuildASTParsesContextReceiverFunctionTypeAlias() throws {
        let rendered = try renderedHandlerType(from: """
        package demo
        typealias Handler = context(A) (Receiver) -> R
        """)
        #expect(rendered == "context(A) (Receiver) -> R")
    }

    @Test
    func testBuildASTParsesNestedGenericContextFunctionTypeAlias() throws {
        let rendered = try renderedHandlerType(from: """
        package demo
        typealias Handler = context(A<B>) (C<D>) -> E
        """)
        #expect(rendered == "context(A<B>) (C<D>) -> E")
    }

    /// KSP-603: a `context(...)` function type in the parameter list is not a
    /// declaration-level context receiver, so the function must not be turned
    /// into an extension function on the first context type.
    @Test
    func testContextFunctionTypeParameterIsNotADeclarationContextReceiver() throws {
        let source = """
        package demo
        fun applyInt(block: context(Int) () -> String): String = "applyInt"
        """
        let (ast, ctx) = try buildASTModule(from: source)
        let funDecl = try #require(firstFunDecl(named: "applyInt", in: ast, interner: ctx.interner))

        #expect(funDecl.receiverType == nil)
        #expect(funDecl.valueParams.count == 1)
        let blockType = try #require(funDecl.valueParams.first?.type)
        #expect(renderTypeRef(blockType, in: ast, interner: ctx.interner) == "context(Int) () -> String")
    }

    /// KUU-915: the first parentheses after `fun <R>` belong to the receiver,
    /// while the parentheses after the name contain the value parameters.
    @Test
    func testSuspendFunctionTypeExtensionReceiver() throws {
        let source = """
        package demo
        internal fun <R> (suspend () -> R).fireAndForget() {
            this.hashCode()
        }
        """
        let (ast, ctx) = try buildASTModule(from: source)
        #expect(!ctx.diagnostics.hasError)
        let function = try #require(firstFunDecl(named: "fireAndForget", in: ast, interner: ctx.interner))
        let receiver = try #require(function.receiverType)
        #expect(renderTypeRef(receiver, in: ast, interner: ctx.interner) == "suspend () -> R")
        #expect(function.valueParams.isEmpty)
    }

    @Test(arguments: [false, true])
    func testSuspendFunctionTypeLocalAnnotations(inLambda: Bool) throws {
        let declarations = """
        val block: suspend () -> Int = { 42 }
        var transform: suspend (Int) -> Int = { it + 1 }
        val receiver: suspend String.() -> Int = { length }
        val nullable: (suspend () -> Int)? = null
        """
        let source = inLambda
            ? "fun main() = runBlocking { \(declarations) }"
            : "fun main() { \(declarations) }"
        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let expected = [
            "block": "suspend () -> Int",
            "transform": "suspend (Int) -> Int",
            "receiver": "suspend String.() -> Int",
            "nullable": "suspend () -> Int?",
        ]
        var checked = Set<String>()
        for expr in ast.arena.exprs {
            guard case let .localDecl(nameID, _, annotation?, _, _, _) = expr else { continue }
            let name = ctx.interner.resolve(nameID)
            guard let expectedType = expected[name] else { continue }
            guard case let .functionType(_, _, _, _, isSuspend, nullable) = ast.arena.typeRef(annotation) else {
                Issue.record("Expected a function type for \(name), not a named 'suspend' type")
                continue
            }
            #expect(isSuspend)
            #expect(nullable == (name == "nullable"))
            #expect(renderTypeRef(annotation, in: ast, interner: ctx.interner) == expectedType)
            checked.insert(name)
        }
        #expect(checked == Set(expected.keys))
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
