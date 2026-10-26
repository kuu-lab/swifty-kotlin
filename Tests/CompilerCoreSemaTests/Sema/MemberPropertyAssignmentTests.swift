@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct MemberPropertyAssignmentTests {
    private static let declarations = """
    import kotlin.reflect.KClass
    class Box<T>(var value: T)
    class Maybe<T>(var value: T?)
    open class Parent<T>(var inherited: T)
    class Child<T>(value: T) : Parent<T>(value)
    abstract class ReadOnlyParent { abstract val x: String }
    interface MutableSibling { var x: String }
    abstract class JoinedProperty : ReadOnlyParent(), MutableSibling
    class JoinedPropertyImpl(override var x: String) : JoinedProperty()
    open class ProtectedSetterParent {
        open var restricted: String = ""
            protected set
    }
    interface ReadOnlySibling { val restricted: String }
    abstract class ProtectedSetterJoin : ProtectedSetterParent(), ReadOnlySibling
    class Plain {
        var value: Int = 0
        var longValue: Long = 0
        var byteValue: Byte = 0
        val fixed: Int = 0
        private var hidden: Int = 0
        var custom: Int = 0
            set(v) { field = v * 2 }
        var restricted: Int = 0
            private set
        fun update() { this.hidden = 1; this.restricted = 2; this.value = 3 }
    }
    class Container<T>(var nested: Box<T>, var callback: (T) -> Int)
    class ClassHolder<T : Any>(var klass: KClass<T>)
    class CallbackHolder<T>(var callback: (Box<T>) -> Int)
    class NullableCallbackHolder<T>(var callback: (Box<T?>) -> Int)
    class Dep<A, B : A>(var callback: (B) -> Int)
    """

    struct AssignmentCase: Sendable {
        let source: String
        let diagnostic: String?
    }

    static let cases: [AssignmentCase] = [
        .init(source: "fun wrong() { val box = Box(1); box.value = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test() { val box = Box(1); box.value = 2 }", diagnostic: nil),
        .init(source: "fun test(box: Plain) { box.value = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Plain) { box.value = 2 }", diagnostic: nil),
        .init(source: "fun test(box: Box<Int>) { box.value = null }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Box<Int?>) { box.value = null }", diagnostic: nil),
        .init(source: "fun test(box: Child<Int>) { box.inherited = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Child<Int>) { box.inherited = 2 }", diagnostic: nil),
        .init(source: "fun <T> test(box: Box<T>, value: T) { box.value = value }", diagnostic: nil),
        .init(source: "fun <T> test(box: Box<T>) { box.value = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Box<in Int>) { box.value = 2 }", diagnostic: nil),
        .init(source: "fun test(box: Box<in Int>) { box.value = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Box<out Int>) { box.value = 2 }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Box<*>) { box.value = 2 }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Box<*>) { box.value = null }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Box<out Int?>) { box.value = null }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Maybe<out Int>) { box.value = null }", diagnostic: nil),
        .init(source: "fun test(box: Maybe<*>) { box.value = null }", diagnostic: nil),
        .init(source: "fun test(box: Maybe<out Int>) { box.value = 2 }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Child<out Int>) { box.inherited = 2 }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Child<in Int>) { box.inherited = 2 }", diagnostic: nil),
        .init(source: "fun test(box: Plain) { box.fixed = 2 }", diagnostic: "KSWIFTK-SEMA-0014"),
        .init(source: "fun test(box: JoinedProperty) { box.x = \"OK\" }", diagnostic: nil),
        .init(source: "fun test(box: JoinedProperty) { box.x = 1 }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: ReadOnlyParent) { box.x = \"no\" }", diagnostic: "KSWIFTK-SEMA-0014"),
        .init(source: "fun test(box: ProtectedSetterJoin) { box.restricted = \"no\" }", diagnostic: "KSWIFTK-SEMA-0041"),
        .init(source: "fun test(box: Plain) { box.hidden = 2 }", diagnostic: "KSWIFTK-SEMA-0040"),
        .init(source: "fun test(box: Plain) { box.restricted = 2 }", diagnostic: "KSWIFTK-SEMA-0040"),
        .init(source: "fun test(box: Plain) { box.missing = 2 }", diagnostic: "KSWIFTK-SEMA-0022"),
        .init(source: "fun test(box: Plain) { box.custom = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Plain) { box.custom = 2 }", diagnostic: nil),
        .init(source: "fun test(box: Plain) { box.longValue = 2; box.byteValue = 127 }", diagnostic: nil),
        .init(source: "fun test(box: Plain) { box.byteValue = 128 }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Plain, value: Int) { box.longValue = value }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Box<Long>) { box.value = 2 }", diagnostic: nil),
        .init(source: "fun test(box: Plain?) { box.value = 2 }", diagnostic: "KSWIFTK-SEMA-0026"),
        .init(source: "fun test(box: Plain?) { if (box != null) box.value = 2 }", diagnostic: nil),
        .init(source: "fun test(box: Container<out Int>, value: Box<Nothing>) { box.nested = value }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Container<in Int>, value: Box<Int>) { box.nested = value }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: Container<out Int>) { box.callback = { it + 1 } }", diagnostic: nil),
        .init(source: "fun test(box: Box<(Int) -> Int>) { box.value = { it + 1 } }", diagnostic: nil),
        .init(source: "fun test(box: Box<(Int) -> Int>) { box.value = { \"wrong\" } }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: ClassHolder<Int>) { box.klass = Int::class }", diagnostic: nil),
        .init(source: "fun test(box: ClassHolder<Int>) { box.klass = String::class }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: ClassHolder<in Int>) { box.klass = Int::class }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: ClassHolder<out Int>) { box.klass = Int::class }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun <B : Box<Int>> test(box: B) { box.value = 1 }", diagnostic: nil),
        .init(source: "fun <B : Box<Int>> test(box: B) { box.value = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun <B : Box<out Int>> test(box: B) { box.value = 1 }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: CallbackHolder<out Int>, fn: (Box<out Int>) -> Int) { box.callback = fn }", diagnostic: nil),
        .init(source: "fun test(box: CallbackHolder<out Int>, fn: (Box<Int>) -> Int) { box.callback = fn }", diagnostic: "KSWIFTK-TYPE-0001"),
        .init(source: "fun test(box: CallbackHolder<in Int>, fn: (Box<in Int>) -> Int) { box.callback = fn }", diagnostic: nil),
        .init(source: "fun test(box: NullableCallbackHolder<out Int>, fn: (Box<out Int?>) -> Int) { box.callback = fn }", diagnostic: nil),
        .init(source: "fun test(box: Dep<Int, *>, fn: (Int) -> Int) { box.callback = fn }", diagnostic: nil),
        .init(source: "fun test(box: Dep<Int, in Nothing>, fn: (Int) -> Int) { box.callback = fn }", diagnostic: nil),
        .init(source: "fun test() { val box = object { var value: Int = 0 }; box.value = 1 }", diagnostic: nil),
        .init(source: "fun test() { val box = object { var value: Int = 0 }; box.value = \"wrong\" }", diagnostic: "KSWIFTK-TYPE-0001"),
    ]

    private func context(_ source: String, libraries: [String] = []) -> CompilationContext {
        let path = "/virtual/member-assignment.kt"
        let ctx = makeCompilationContext(inputs: [path], searchPaths: libraries, includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: cases)
    func sourceAssignments(example: AssignmentCase) throws {
        let ctx = context(Self.declarations + "\n" + example.source)
        try runSema(ctx)
        assertResult(example, ctx: ctx)
    }

    @Test(arguments: ["v1", "v2", "v3"], [false, true])
    func freshLibraryAssignments(format: String, includeNonPublic: Bool) throws {
        try withFreshLibrary(Self.declarations, format: format, includeNonPublic: includeNonPublic) { library in
            for example in Self.cases {
                let consumer = context(example.source, libraries: [library])
                try runSema(consumer)
                // Private declarations omitted from public metadata must still
                // fail during Sema, rather than becoming an unresolved KIR call.
                let expected = !includeNonPublic && example.source.contains("box.hidden")
                    ? AssignmentCase(source: example.source, diagnostic: "KSWIFTK-SEMA-0022") : example
                assertResult(expected, ctx: consumer)
            }
        }
    }

    private func withFreshLibrary(
        _ source: String, format: String, includeNonPublic: Bool = false,
        body: (String) throws -> Void
    ) throws {
        let producer = context(source)
        try runSema(producer)
        #expect(!producer.diagnostics.hasError, "\(producer.diagnostics.diagnostics)")
        let sema = try #require(producer.sema)
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: sema.symbols, types: sema.types, moduleName: "AssignmentProducer",
            interner: producer.interner, functionLinkNames: [:], includeNonPublic: includeNonPublic
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "{\"formatVersion\":\(format == "v3" ? 2 : 1),\"moduleName\":\"AssignmentProducer\",\"metadata\":\"metadata.bin\"}"
            .write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let data: Data
        switch format {
        case "v1": data = Data(encoder.serialize(records).utf8)
        case "v2": data = Data(encoder.serializeIndexed(records).utf8)
        default: data = encoder.serializeCompactIndexed(records)
        }
        try data.write(to: directory.appendingPathComponent("metadata.bin"))
        try body(directory.path)
    }

    @Test(arguments: ["v1", "v2", "v3"])
    func independentLibrariesKeepTheirOwnUpperBounds(format: String) throws {
        try withFreshLibrary("interface First<T : Int> { var callback: (T) -> Int }", format: format) { first in
            try withFreshLibrary("interface Second<T : String> { var callback: (T) -> Int }", format: format) { second in
                let valid = context("""
                fun test(first: First<*>, second: Second<*>, fi: (Int) -> Int, fs: (String) -> Int) {
                    second.callback = fs
                    first.callback = fi
                }
                """, libraries: [first, second])
                try runSema(valid)
                #expect(!valid.diagnostics.hasError, "\(valid.diagnostics.diagnostics)")
                let invalid = context("""
                fun test(first: First<*>, second: Second<*>, fs: (String) -> Int) {
                    second.callback = fs
                    first.callback = fs
                }
                """, libraries: [first, second])
                try runSema(invalid)
                assertHasDiagnostic("KSWIFTK-TYPE-0001", in: invalid)
            }
        }
    }

    private func assertResult(_ example: AssignmentCase, ctx: CompilationContext) {
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        if let code = example.diagnostic {
            #expect(errors.contains { $0.code == code }, "\(example.source): \(errors)")
            #expect(errors.allSatisfy { $0.code == code }, "Unexpected diagnostics for \(example.source): \(errors)")
        } else {
            #expect(errors.isEmpty, "\(example.source): \(errors)")
        }
    }

    @Test(arguments: [
        "class Init { val value: Long; init { this.value = 2 } }",
        "class Init { val value: Long; constructor() { this.value = 2 } }"
    ])
    func ownValInitialization(source: String) throws {
        let ctx = context(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func initializerCannotAssignAnotherInstancesVal() throws {
        let ctx = context("class Init(other: Init) { val value: Int = 0; init { other.value = 2 } }")
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
    }

    @Test
    func incompatibleInheritedMutablePropertiesCannotBeWritten() throws {
        let ctx = context("""
        interface StringValue { var value: String }
        interface IntValue { var value: Int }
        abstract class AmbiguousValue : StringValue, IntValue
        fun write(value: AmbiguousValue) { value.value = "x" }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Incompatible inherited setters must not be accepted.")
    }

    @Test
    func contextualLiteralsBindToPropertyTypes() throws {
        let ctx = context(Self.declarations + "\nfun test(box: Plain) { box.longValue = 2; box.byteValue = -128 }")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for (name, type) in [("longValue", sema.types.longType), ("byteValue", sema.types.byteType)] {
            let assignment = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberAssign(_, callee, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == name
            })
            guard case let .memberAssign(_, _, value, _) = ast.arena.expr(assignment) else { continue }
            #expect(sema.bindings.exprType(for: value) == type)
        }
    }
}
