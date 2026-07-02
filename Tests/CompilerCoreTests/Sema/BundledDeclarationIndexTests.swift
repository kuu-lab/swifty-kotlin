@testable import CompilerCore
import Foundation
import Testing

@Suite
struct BundledDeclarationIndexTests {
    @Test
    func astBuildQualifiesSamePackageNestedReceiverPaths() throws {
        let (ast, ctx) = try buildBundledAST(
            """
            package kotlin.collections

            class Outer {
                class Inner
            }

            fun Outer.Inner.touch(count: Int) {}
            """
        )

        let index = BundledDeclarationIndex.build(ast: ast, sourceManager: ctx.sourceManager)
        let qualifiedOwner = intern(["kotlin", "collections", "Outer", "Inner"], ctx.interner)
        let unqualifiedOwner = intern(["Outer", "Inner"], ctx.interner)
        let touch = ctx.interner.intern("touch")

        #expect(index.contains(owner: qualifiedOwner, name: touch, arity: 1))
        #expect(!index.contains(owner: unqualifiedOwner, name: touch, arity: 1))
    }

    @Test
    func astBuildCollectsNestedInterfaceMembers() throws {
        let (ast, ctx) = try buildBundledAST(
            """
            package kotlin.collections

            class Outer {
                interface Cursor {
                    fun advance()
                }
            }
            """
        )

        let index = BundledDeclarationIndex.build(ast: ast, sourceManager: ctx.sourceManager)
        let owner = intern(["kotlin", "collections", "Outer", "Cursor"], ctx.interner)
        let advance = ctx.interner.intern("advance")

        #expect(index.contains(owner: owner, name: advance, arity: 0))
    }

    @Test
    func symbolTableBuildUsesInterfaceReceiverFQName() throws {
        let sourceManager = SourceManager()
        let fileID = sourceManager.addFile(path: "__bundled_interface.kt", contents: Data("".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 0)
        )
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()

        let interfaceName = interner.intern("Cursor")
        let ownerFQName = intern(["kotlin", "collections", "Cursor"], interner)
        let interfaceID = symbols.define(
            kind: .interface,
            name: interfaceName,
            fqName: ownerFQName,
            declSite: range,
            visibility: .public
        )
        let functionName = interner.intern("advance")
        let functionID = symbols.define(
            kind: .function,
            name: functionName,
            fqName: intern(["kotlin", "collections", "advance"], interner),
            declSite: range,
            visibility: .public
        )
        let receiverType = types.make(.classType(ClassType(classSymbol: interfaceID)))
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: types.unitType
            ),
            for: functionID
        )

        let index = BundledDeclarationIndex.build(
            sourceManager: sourceManager,
            symbols: symbols,
            types: types
        )

        #expect(index.contains(owner: ownerFQName, name: functionName, arity: 0))
    }

    private func buildBundledAST(_ source: String) throws -> (ASTModule, CompilationContext) {
        let path = "__bundled_test.kt"
        let ctx = makeCompilationContext(inputs: [path])
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        return (try #require(ctx.ast), ctx)
    }

    private func intern(_ parts: [String], _ interner: StringInterner) -> [InternedString] {
        parts.map { interner.intern($0) }
    }
}
