#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KClassCaptureInferenceTests {
    private static let declarations = """
    import kotlin.reflect.KClass
    class Box<T>(var value: T)
    fun <T : Any> KClass<T>.consume(value: T): Int = 7
    fun <T : Any> KClass<T>.produce(value: T): T = value
    fun <T : Any> KClass<T>.box(value: T): Box<T> = Box(value)
    fun <T : Any> KClass<T>.list(value: T): List<T> = null as List<T>
    fun <T : Any> KClass<T>.read(): T = 42 as T
    fun <T : Any> KClass<T>.same(): KClass<T> = this
    """

    @Test(arguments: [
        ("Int", "k.consume(42)", true),
        ("Any", "k.consume(42)", true),
        ("in Int", "k.consume(42)", true),
        ("out Any", "k.consume(42)", false),
        ("*", "k.consume(42)", false),
        ("Int", "k.consume(\"wrong\")", false),
        ("in Int", "k.consume(\"wrong\")", false),
        ("in Int", "k.consume(null)", false),
        ("Int", "k.consume<Int>(42)", true),
        ("Any", "k.consume<Any>(42)", true),
        ("in Int", "k.consume<Int>(42)", false),
        ("in Int", "k.consume<Any>(42)", false),
        ("out Any", "k.consume<Any>(42)", false),
        ("*", "k.consume<Any>(42)", false),
        ("in Int", "val result: Any = k.produce(42)", true),
        ("in Int", "val result: Int = k.produce(42)", false),
        ("in Int", "val result: Box<out Any> = k.box(42)", true),
        ("in Int", "val result: Box<in Int> = k.box(42)", true),
        ("in Int", "val result: Box<Int> = k.box(42)", false),
        ("in Int", "val result: Box<Any> = k.box(42)", false),
        ("in Int", "val result: List<Any> = k.list(42)", true),
        ("in Int", "val result: List<Int> = k.list(42)", false),
        ("in Int", "val result = k.box(42); result.value = 43", true),
        ("in Int", "val result = k.box(42); result.value = \"wrong\"", false),
        ("out Int", "val result: Int = k.read()", true),
        ("out Any", "val result: Any = k.read()", true),
        ("in Int", "val result: Any = k.read()", true),
        ("*", "val result: Any = k.read()", true),
        ("in Int", "val result: Int = k.read()", false),
        ("*", "val result: Int = k.read()", false),
        ("in Int", "val result: KClass<Any> = k.same()", false),
        ("in Int", "val result: KClass<Int> = k.same()", false),
        ("in Int", "val result: KClass<out Any> = k.same()", true),
        ("in Int", "val result: KClass<in Int> = k.same()", true),
        ("in Int", "val result: KClass<in String> = k.same()", false),
        ("out Int", "val result: KClass<out Int> = k.same()", true),
        ("out Int", "val result: Int = k.read() + 1", true),
        ("out Int", "val result: Int = -k.read()", true),
        ("out Boolean", "val result: Boolean = !k.read()", true),
        ("out String", "val result: String = k.read() + \"x\"", true),
        ("in Int", "k.read() + 1", false),
        ("in Int", "-k.read()", false),
        ("in Int", "val result: Int = 1 + k.read()", false),
        ("out Boolean", "-k.read()", false),
    ])
    func projectedReceiverMatrix(projection: String, statement: String, accepted: Bool) throws {
        let source = Self.declarations + "\nfun probe(k: KClass<\(projection)>) { \(statement) }"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == !accepted, "\(source)\n\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        "val k = Int::class; k.consume(42)",
        "val k = kotlin.Int::class; k.consume(42)",
        "val k: KClass<Int> = Int::class; k.consume(42)",
        "val k: KClass<in Int> = Int::class; k.consume(42)",
        "val k: KClass<in Int> = Any::class; k.consume(42)",
    ])
    func classLiteralAndStoredReceivers(statement: String) throws {
        try withTemporaryFile(contents: Self.declarations + "\nfun probe() { \(statement) }") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func capturedBoundsAndIdentityRemainDistinct() throws {
        let types = TypeSystem()
        let parameter = SymbolID(rawValue: 1)
        let first = types.makeCapturedType(parameter: parameter, lower: types.intType, upper: types.anyType)
        let second = types.makeCapturedType(parameter: parameter, lower: types.intType, upper: types.anyType)
        #expect(types.isSubtype(types.intType, first))
        #expect(!types.isSubtype(types.stringType, first))
        #expect(types.isSubtype(first, types.anyType))
        #expect(!types.isSubtype(first, types.intType))
        #expect(!types.isSubtype(first, second))
        #expect(types.isSubtype(first, types.makeNullable(first)))
        let mapping = types.makeTypeVarBySymbol([parameter])
        let variable = try #require(mapping[parameter])
        #expect(types.substituteTypeParameters(in: first, substitution: [variable: types.intType], typeVarBySymbol: mapping) == first)
    }

    @Test func capturedUpperBoundSupportsGenericMembers() throws {
        let source = Self.declarations + """
        \nclass Foo<U>(val value: U) { fun get(): U = value }
        fun probe(k: KClass<out Foo<String>>) {
            val result = k.read()
            val property: String = result.value
            val method: String = result.get()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func metadataApproximationPreservesWritableAndNullableBounds() throws {
        let types = TypeSystem()
        let captured = types.makeCapturedType(parameter: SymbolID(rawValue: 1), lower: types.intType, upper: types.anyType)
        let boxSymbol = SymbolID(rawValue: 2)
        let sink = types.make(.classType(ClassType(classSymbol: boxSymbol, args: [.in(captured)])))
        let expectedSink = types.make(.classType(ClassType(classSymbol: boxSymbol, args: [.in(types.intType)])))
        #expect(types.approximatingCapturedTypes(in: sink) == expectedSink)
        let out = types.makeCapturedType(parameter: SymbolID(rawValue: 1), lower: types.nothingType, upper: types.intType)
        let nullable = types.makeNullable(out)
        let box = types.make(.classType(ClassType(classSymbol: boxSymbol, args: [.invariant(nullable)])))
        let approximated = types.approximatingCapturedTypes(in: box)
        let acceptsNull = types.make(.classType(ClassType(classSymbol: boxSymbol, args: [.out(types.makeNullable(types.intType))])))
        let nonNull = types.make(.classType(ClassType(classSymbol: boxSymbol, args: [.out(types.intType)])))
        #expect(types.isSubtype(approximated, acceptsNull))
        #expect(!types.isSubtype(approximated, nonNull))
    }

    @Test func capturedUpperBoundsSupportBuiltinOperators() throws {
        let source = Self.declarations + """
        \nfun add(k: KClass<out Int>): Int = k.read() + 1
        fun neg(k: KClass<out Int>): Int = -k.read()
        fun cmp(k: KClass<out Int>): Boolean = k.read() < 100
        fun str(k: KClass<out String>): String = k.read() + "x"
        fun bool(k: KClass<out Boolean>): Boolean = !k.read()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
