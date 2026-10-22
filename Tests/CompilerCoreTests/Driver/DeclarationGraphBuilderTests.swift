#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct DeclarationGraphBuilderTests {
    private func graph(_ source: String) throws -> DeclarationDependencyGraph {
        let dir = NSTemporaryDirectory() + "kswk-decl-fixed"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/a.kt"
        try source.write(toFile: path, atomically: true, encoding: .utf8)
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        let ast = try #require(ctx.ast)
        return DeclarationGraphBuilder.build(ast: ast, sourceManager: ctx.sourceManager, interner: ctx.interner)
    }

    private func invalidatedNames(_ old: String, _ new: String) throws -> Set<String> {
        let newGraph = try graph(new)
        let ids = newGraph.invalidated(since: try graph(old))
        return Set(ids.map { String($0.split(separator: "::").last ?? "") })
    }

    private let base = """
    package p
    fun helper(x: Int): Int { return x + 1 }
    fun user(): Int { return helper(2) }
    fun other(): Int { return 7 }
    """

    @Test
    func identicalSourcesInvalidateNothing() throws {
        #expect(try invalidatedNames(base, base).isEmpty)
    }

    @Test
    func bodyEditInvalidatesOnlyThatFunction() throws {
        let edited = base.replacingOccurrences(of: "return x + 1", with: "return x + 2")
        #expect(try invalidatedNames(base, edited) == ["p.helper#0"])
    }

    @Test
    func signatureEditInvalidatesCallersButNotUnrelatedFunctions() throws {
        let edited = base.replacingOccurrences(of: "fun helper(x: Int): Int", with: "fun helper(x: Long): Int")
        #expect(try invalidatedNames(base, edited) == ["p.helper#0", "p.user#0"])
    }

    @Test
    func inferredReturnTypeBodyEditCountsAsSignatureChange() throws {
        let old = "package p\nfun f() = 1\nfun g(): Int { return f() }\nfun h(): Int { return 3 }\n"
        let new = old.replacingOccurrences(of: "fun f() = 1", with: "fun f() = \"s\"")
        #expect(try invalidatedNames(old, new) == ["p.f#0", "p.g#0"])
    }

    @Test
    func inlineBodyEditInvalidatesCallers() throws {
        let old = "package p\ninline fun f(): Int { return 1 }\nfun g(): Int { return f() }\nfun h(): Int { return 3 }\n"
        let new = old.replacingOccurrences(of: "return 1", with: "return 2")
        #expect(try invalidatedNames(old, new) == ["p.f#0", "p.g#0"])
    }

    @Test
    func operatorConventionDeclarationInvalidatesUnitsThatNeverSpellItsName() throws {
        let old = """
        package p
        class V(val x: Int)
        operator fun V.plus(o: V): V { return V(x + o.x) }
        fun use(a: V, b: V): V { return a + b }
        """
        let new = old.replacingOccurrences(of: "operator fun V.plus(o: V): V", with: "operator fun V.plus(o: V): V?")
        let names = try invalidatedNames(old, new)
        #expect(names.contains("p.plus#0"))
        #expect(names.contains("p.use#0"))
    }

    @Test
    func addingAnOverloadDoesNotChangeUnrelatedBodiesHashes() throws {
        let added = base + "\nfun brandNew(): Int { return 0 }\n"
        #expect(try invalidatedNames(base, added) == ["p.brandNew#0"])
    }
}
#endif
