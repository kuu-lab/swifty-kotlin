@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InheritedMemberOverloadWithoutDefaultsTests {
    @Test
    func inheritedMemberBindingArgumentsExactlyBeatsNearerDefaultedMember() throws {
        let ctx = try semaContext(from: """
        interface Dec {
            fun describe(value: String): String = "Dec"
        }
        abstract class AbstractDec : Dec {
            open fun describe(value: String, previous: String? = null): String = "AbstractDec"
        }
        class MyDec : AbstractDec()
        open class Base {
            fun describe(value: String): String = "Base"
        }
        open class Mid : Base() {
            open fun describe(value: String, previous: String? = null): String = "Mid"
        }
        fun Base.ext(value: String): String = "Base.ext"
        fun Mid.ext(value: String, previous: String? = null): String = "Mid.ext"

        fun classMember(): String = Mid().describe("ok")
        fun explicitDefault(): String = Mid().describe("ok", null)
        fun interfaceMember(): String = MyDec().describe("ok")
        fun abstractReceiver(d: AbstractDec): String = d.describe("ok")
        fun extensionReceiver(): String = Mid().ext("ok")
        """, includeStdlib: false)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var owners: [String] = []
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let binding = sema.bindings.callBinding(for: id),
                  let callee = sema.symbols.symbol(binding.chosenCallee),
                  ["describe", "ext"].contains(ctx.interner.resolve(callee.name))
            else { continue }
            if let parentID = sema.symbols.parentSymbol(for: callee.id),
               let parent = sema.symbols.symbol(parentID),
               callee.fqName == parent.fqName + [callee.name]
            {
                owners.append(ctx.interner.resolve(parent.name))
            } else {
                let arity = sema.symbols.functionSignature(for: callee.id)?.parameterTypes.count ?? -1
                owners.append("ext/\(arity)")
            }
        }
        #expect(owners == ["Base", "Mid", "Dec", "Dec", "ext/2"], "\(owners)")
    }
}
