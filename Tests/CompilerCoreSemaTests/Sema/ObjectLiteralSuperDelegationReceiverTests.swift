#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// KUU-4517: an object literal's supertype constructor arguments are checked
/// inside the object's own header scope, where the superclass's companion
/// object is the innermost implicit receiver. An unqualified `this` there
/// binds to the companion — `object : Base(this)` passes `Base.Companion`,
/// not the enclosing extension receiver — and companion members resolve
/// without a qualifier, matching kotlinc's overload choice.
@Suite
struct ObjectLiteralSuperDelegationReceiverTests {
    private func classSymbol(
        named name: String,
        in ctx: CompilationContext
    ) throws -> SymbolID {
        let sema = try #require(ctx.sema)
        let matches = sema.symbols.lookupAll(fqName: [ctx.interner.intern(name)])
        return try #require(matches.first {
            sema.symbols.symbol($0)?.kind == .class
        })
    }

    private func thisExprIDs(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext
    ) -> [ExprID] {
        allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            if case .thisRef(label: nil, _) = expr { return true }
            return false
        }
    }

    @Test
    func unqualifiedThisPrefersSuperclassCompanionOverExtensionReceiver() throws {
        let source = """
        open class OverloadedReceiver(val selected: String) {
            constructor(value: OverloadedReceiver) : this("extension")
            constructor(value: Companion) : this("companion")
            companion object
        }
        fun OverloadedReceiver.chooseReceiver(): String =
            object : OverloadedReceiver(this) {}.selected
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let thisExpr = try #require(thisExprIDs(in: ast, path: path, ctx: ctx).first)
            let base = try classSymbol(named: "OverloadedReceiver", in: ctx)
            let companion = try #require(sema.symbols.companionObjectSymbol(for: base))
            #expect(sema.bindings.identifierSymbol(for: thisExpr) == companion)
        }
    }

    @Test
    func unqualifiedCompanionMemberResolvesInSuperConstructorArgument() throws {
        let source = """
        open class Base(val s: String) {
            companion object { val TAG = "companion" }
        }
        fun Base.make(): String = object : Base(TAG) {}.s
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let tagName = ctx.interner.intern("TAG")
            let tagExpr = try #require(allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .nameRef(name, _) = expr else { return false }
                return name == tagName
            }.first)
            let base = try classSymbol(named: "Base", in: ctx)
            let companion = try #require(sema.symbols.companionObjectSymbol(for: base))
            let bound = try #require(sema.bindings.identifierSymbol(for: tagExpr))
            #expect(sema.symbols.parentSymbol(for: bound) == companion)
        }
    }

    @Test
    func unqualifiedThisFallsBackToExtensionReceiverWithoutCompanion() throws {
        let source = """
        open class AnyReceiver(val value: Any?)
        open class Marker
        fun Marker.probe(): Any? = object : AnyReceiver(this) {}.value
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let thisExpr = try #require(thisExprIDs(in: ast, path: path, ctx: ctx).first)
            let marker = try classSymbol(named: "Marker", in: ctx)
            let thisType = try #require(sema.bindings.exprType(for: thisExpr))
            #expect(TypeCheckHelpers().nominalSymbol(of: thisType, types: sema.types) == marker)
        }
    }

    @Test
    func namedObjectSuperDelegationSeesSuperclassCompanionMembers() throws {
        let source = """
        open class Base(val s: String) {
            companion object { val TAG = "companion" }
        }
        object Impl : Base(TAG)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let tagName = ctx.interner.intern("TAG")
            let tagExpr = try #require(allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .nameRef(name, _) = expr else { return false }
                return name == tagName
            }.first)
            let base = try classSymbol(named: "Base", in: ctx)
            let companion = try #require(sema.symbols.companionObjectSymbol(for: base))
            let bound = try #require(sema.bindings.identifierSymbol(for: tagExpr))
            #expect(sema.symbols.parentSymbol(for: bound) == companion)
        }
    }
}
#endif
