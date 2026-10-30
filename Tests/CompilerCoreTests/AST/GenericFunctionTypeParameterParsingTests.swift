@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericFunctionTypeParameterParsingTests {
    @Test(arguments: [
        ("fun<TItem>", "where"),
        ("fun <TItem>", "where"),
        ("fun<TItem>", "filter"),
    ])
    func genericExtensionFunctionAcceptsTypeParametersBeforeReceiver(
        _ functionHead: String,
        _ functionName: String
    ) throws {
        let source = """
        infix \(functionHead) Iterable<TItem>.\(functionName)(predicate : (TItem)->Boolean) : Iterable<TItem> {
            return this
        }
        """
        let (ast, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let function = try #require(ast.files.flatMap(\.topLevelDecls).compactMap { id -> FunDecl? in
            guard case let .funDecl(value) = ast.arena.decl(id) else { return nil }
            return value
        }.first)
        #expect(context.interner.resolve(function.name) == functionName)
        #expect(function.typeParams.map { context.interner.resolve($0.name) } == ["TItem"])
        #expect(function.receiverType != nil)
        #expect(function.valueParams.count == 1)
    }

    @Test
    func functionNamedWhereStillParsesItsActualWhereClause() throws {
        let (ast, context) = try buildASTModule(
            from: "fun<T> T.where(): T where T : Any = this",
            includeStdlib: false
        )

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let function = try #require(ast.files.flatMap(\.topLevelDecls).compactMap { id -> FunDecl? in
            guard case let .funDecl(value) = ast.arena.decl(id) else { return nil }
            return value
        }.first)
        #expect(context.interner.resolve(function.name) == "where")
        #expect(function.typeParams.first?.upperBounds.count == 1)
    }
}
