import Foundation
@testable import CompilerCore
import Testing

@Suite
struct GenericExtensionPropertyTypeCheckingTests {
    private func check(_ source: String) throws -> CompilationContext {
        let input = "/virtual/generic-property.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data(source.utf8))
        try runSema(context)
        return context
    }

    @Test(arguments: ["noReceiver", "returnOnly", "bound", "whereBound", "whereInlineBound", "whereAnnotatedBound", "functionArgument", "nominalArgument", "setterArgument", "nullableSetterBound", "nullableCompoundBound", "nullableIncrementBound", "leakedParameter", "variance", "duplicate", "whereType", "localReified", "localBounds", "erasedReifiedArgument", "inlineAnnotation", "partlyInline"])
    func invalidGenericPropertiesRemainRejected(_ mode: String) throws {
        let body: String = switch mode {
        case "noReceiver": "val <T> bad: T get() = null"
        case "returnOnly": "val <T, U> Box<T>.bad: U? get() = null"
        case "bound": "val <T : Any> Box<T>.bounded: T get() = value\nfun bad(box: Box<String?>) = box.bounded"
        case "whereBound": "val <T> Box<T>.bounded: T where T : Any get() = value\nfun bad(box: Box<String?>) = box.bounded"
        case "whereInlineBound": "val <T> Box<T>.bounded: T where T : Any inline get() = value\nfun bad(box: Box<String?>) = box.bounded"
        case "whereAnnotatedBound": "annotation class A\nval <T> Box<T>.bounded: T where T : Any @A get() = value\nfun bad(box: Box<String?>) = box.bounded"
        case "functionArgument": "val <T> Box<T>.callback: (T) -> T get() = { it }\nfun bad(box: Box<String>) = box.callback(1)"
        case "nominalArgument": "class Action<T> { operator fun invoke(value: T): T = value }\nval <T> Box<T>.callback: Action<T> get() = Action<T>()\nfun bad(box: Box<String>) = box.callback(1)"
        case "setterArgument": "var <T> Box<T>.entry: T get() = value; set(v) { value = v }\nfun bad(box: Box<String>) { box.entry = 1 }"
        case "nullableSetterBound": "var <T : Any> T.n: Int get() = 0; set(v) {}\nfun bad(s: String?) { s.n = 1 }"
        case "nullableCompoundBound": "var <T : Any> T.n: Int get() = 0; set(v) {}\nfun bad(s: String?) { s.n += 1 }"
        case "nullableIncrementBound": "var <T : Any> T.n: Int get() = 0; set(v) {}\nfun bad(s: String?) { s.n++ }"
        case "leakedParameter": "val <T> Box<T>.entry: T get() = value\nfun bad(value: T) = value"
        case "variance": "val <out T> Box<T>.entry: T get() = value"
        case "localBounds": "fun bad() { val p = object { val <T> T.bad: Int? where T : Int, T : String get() = null } }"
        case "erasedReifiedArgument": "inline val <reified T> T.kind: (Any) -> Boolean get() = { it is T }\nfun <U> bad(u: U): Boolean = u.kind(1)"
        case "inlineAnnotation": "annotation class inline\nval <reified T> T.kind: (Any) -> Boolean\n    @inline get() = { it is T }"
        case "partlyInline": "var <reified T> Box<T>.entry: T\n    inline get() = value\n    set(v) { value = v }"
        case "localReified": """
        fun bad() {
            val p = object {
                val <reified T> T.kind: (Any) -> Boolean get() = { it is T }
                fun use(): Boolean = 1.kind(1)
            }
            p.use()
        }
        """
        case "whereType": "class where\nval wrong: where = 1"
        default: "val <T, T> Box<T>.entry: T get() = value"
        }
        let context = try check("class Box<T>(var value: T)\n" + body)
        #expect(context.diagnostics.hasError, "\(mode): \(context.diagnostics.diagnostics)")
        if ["localReified", "erasedReifiedArgument", "inlineAnnotation", "partlyInline"].contains(mode) {
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0020" })
        }
        if mode == "localBounds" {
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0305" })
        }
        if ["noReceiver", "returnOnly", "variance", "duplicate"].contains(mode) {
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0005" })
        }
    }

    @Test
    func getterAndSetterCanUseTheirOwnTypeParameters() throws {
        let context = try check("""
        class Box<T>(var value: T)
        fun <T> identity(value: T): T = value
        var <T> Box<T>.entry: T
            get() = identity<T>(value)
            set(v) { value = identity<T>(v) }
        """)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func nullableReceiverIsValidWithoutANonNullBound() throws {
        let context = try check("""
        var <T> T.n: Int get() = 0; set(v) {}
        fun valid(s: String?) { s.n = 1; s.n += 1; s.n++ }
        """)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}
