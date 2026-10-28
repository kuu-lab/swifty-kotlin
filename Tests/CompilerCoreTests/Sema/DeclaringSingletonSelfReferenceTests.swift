#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct DeclaringSingletonSelfReferenceTests {
    @Test(arguments: [false, true])
    func anonymousObjectMemberCanCallItsDeclaringSingleton(usesPropertyInitializer: Bool) throws {
        TestStdlibCache.shared.prepare()
        let singleton = usesPropertyInitializer
            ? """
              object Test {
                  val fn: IFn = object : IFn {
                      override fun invoke(): String = Test.ok()
                  }
                  fun ok() = "OK"
              }
              """
            : """
              abstract class Base(val fn: IFn)
              object Test : Base(object : IFn {
                  override fun invoke(): String = Test.ok()
              }) {
                  fun ok() = "OK"
              }
              """
        let source = """
        interface IFn { operator fun invoke(): String }
        \(singleton)
        fun box(): String = Test.fn()
        fun main() { println(box()) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                allowDefaultStdlibLibrary: true
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(memberCallExprIDs(
                named: "ok", in: ast, interner: ctx.interner
            ).first)
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            #expect(sema.symbols.symbol(chosen)?.fqName.map(ctx.interner.resolve) == ["Test", "ok"])
        }
    }
}
#endif
