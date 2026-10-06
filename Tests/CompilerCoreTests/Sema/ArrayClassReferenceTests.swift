@testable import CompilerCore
import Testing

@Suite
struct ArrayClassReferenceTests {
    private let classifiers = """
    package kotlin
    class Array<T>
    class List<T>
    class Pair<A, B>
    """

    @Test(arguments: ["Array<Int>", "kotlin.Array<String>", "Array<Array<String>>", "Array<out Int>", "Array<Int?>"])
    func concreteArrayClassLiteralResolves(receiver: String) throws {
        try withTemporaryFile(contents: classifiers + "\nfun literal() = \(receiver)::class") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let ref = try #require(firstExprID(in: ast) { id, expr in
                guard isUserSourceExpr(id, in: ctx), case .callableRef = expr else { return false }
                return true
            })
            let target = try #require(sema.bindings.classRefTargetType(for: ref))
            let owner = try #require(resolveClassType(target, sema: sema))
            let symbol = try #require(sema.symbols.symbol(owner.classSymbol))
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "Array"])
            #expect(owner.args.count == 1)
            #expect(!sema.bindings.boundClassRefExprs.contains(ref))
        }
    }

    @Test(arguments: [
        "List<Int>", "Array<*>", "Array<Int, String>", "Array<List<Int>>",
        "Array<Pair<Int, Int>>", "Array<(Int) -> String>", "Array<Int>?", "Array<Int>? ",
    ])
    func invalidTypeArgumentsRemainRejected(receiver: String) throws {
        try withTemporaryFile(contents: classifiers + "\nfun literal() = \(receiver)::class") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func nonReifiedArrayElementIsRejected() throws {
        try withTemporaryFile(contents: classifiers + "\nfun <T> literal() = Array<T>::class") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }
}
