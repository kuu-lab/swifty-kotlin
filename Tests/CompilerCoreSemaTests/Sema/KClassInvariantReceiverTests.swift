@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct KClassInvariantReceiverTests {
    private static let arguments = ["Int", "Any", "out Any", "in Int", "*"]
    // Kotlin/JVM 2.3.10: row = actual argument, column = required argument.
    private static let accepted = [
        [true, false, true, true, true],
        [false, true, true, true, true],
        [false, false, true, false, true],
        [false, false, true, true, true],
        [false, false, true, false, true],
    ]

    private func makeKClassContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func exactStarReceiverReproducerIsRejected() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun KClass<Any>.fixed(): Int = 7
        fun wrong(k: KClass<*>): Int = k.fixed()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && ["KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0024"].contains($0.code)
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: 0..<5, 0..<5)
    func assignmentAndFixedReceiverMatrix(actual: Int, required: Int) throws {
        let from = Self.arguments[actual]
        let to = Self.arguments[required]
        for body in [
            "fun probe(k: KClass<\(from)>): KClass<\(to)> = k",
            "fun KClass<\(to)>.fixed(): Int = 7\nfun probe(k: KClass<\(from)>): Int = k.fixed()",
        ] {
            let ctx = makeKClassContext("import kotlin.reflect.KClass\n" + body)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError == Self.accepted[actual][required],
                    "\(body): \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: ["Int", "Any", "out Any"])
    func inferredReadOnlyGenericReceiverIsAccepted(argument: String) throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun <T : Any> KClass<T>.read(): Int = 7
        fun probe(k: KClass<\(argument)>): Int = k.read()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: Self.arguments)
    func explicitGenericArgumentDoesNotEraseProjection(argument: String) throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun <T : Any> KClass<T>.read(): Int = 7
        fun probe(k: KClass<\(argument)>): Int = k.read<Any>()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError == (argument == "Any"), "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["Int", "Any", "out Any", "*"])
    func genericReceiverCannotConsumeCapturedProjection(argument: String) throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun <T : Any> KClass<T>.consume(value: T): Int = 7
        fun probe(k: KClass<\(argument)>): Int = k.consume(42)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError == ["Int", "Any"].contains(argument),
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test func localOutProjectionCannotBecomeInvariantReceiver() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun KClass<Any>.fixed(): Int = 7
        fun probe(): Int {
            val k: KClass<out Any> = Int::class
            return k.fixed()
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func localOutProjectionRemainsAssignable() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun probe(): KClass<out Any> {
            val k: KClass<out Any> = Int::class
            return k
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func boundClassReferenceRetainsOutProjection(projected: Bool) throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun KClass<\(projected ? "out Int" : "Int")>.fixed(): Int = 7
        fun probe(): Int = 42::class.fixed()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError == projected, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func boundClassReferenceStillUsesDynamicLookupAndEvaluatesReceiverOnce() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        class Item
        fun makeItem(): Item = Item()
        fun probe(): KClass<out Item> = makeItem()::class
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        #expect(kirCalls(to: .kClassOf, in: body, interner: ctx.interner).count == 1)
        let factory = try findKIRFunction(named: "makeItem", in: module, interner: ctx.interner)
        #expect(kirCalls(to: factory.symbol, in: body).count == 1)
    }

    @Test(arguments: [false, true])
    func exportedReceiverProjectionsSurviveMetadataImport(indexed: Bool) throws {
        let declarations = Self.arguments.enumerated().map { index, argument in
            "fun KClass<\(argument)>.fixed\(index)(): Int = 7"
        }.joined(separator: "\n")
        let producer = makeKClassContext("package fixture\nimport kotlin.reflect.KClass\n" + declarations)
        try runSema(producer)
        #expect(!producer.diagnostics.hasError, "\(producer.diagnostics.diagnostics)")
        let sema = try #require(producer.sema)
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: sema.symbols, types: sema.types, moduleName: "KClassReceivers",
            interner: producer.interner, functionLinkNames: [:]
        ).filter {
            $0.fqName == "fixture" || $0.fqName.hasPrefix("fixture.")
                || $0.fqName == "kotlin.reflect.KClass"
        }
        #expect(records.filter { $0.kind == .function && $0.fqName.hasPrefix("fixture.") }.count == 5)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        {"formatVersion":1,"moduleName":"KClassReceivers","metadata":"metadata.bin"}
        """.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let metadata = indexed ? encoder.serializeIndexed(records) : encoder.serialize(records)
        try metadata.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "fun main() {}") { path in
            let consumer = makeCompilationContext(inputs: [path], searchPaths: [directory.path], includeStdlib: false)
            try runSema(consumer)
            #expect(!consumer.diagnostics.hasError, "\(consumer.diagnostics.diagnostics)")
            let imported = try #require(consumer.sema)
            let receivers = try (0..<5).map { index in
                let symbol = try #require(imported.symbols.lookup(
                    fqName: ["fixture", "fixed\(index)"].map(consumer.interner.intern)
                ))
                return try #require(imported.symbols.functionSignature(for: symbol)?.receiverType)
            }
            for actual in 0..<5 {
                for required in 0..<5 {
                    #expect(imported.types.isSubtype(receivers[actual], receivers[required])
                            == Self.accepted[actual][required], "Imported receiver \(actual) -> \(required)")
                }
            }
        }
        try withTemporaryFile(contents: """
        import kotlin.reflect.KClass
        import fixture.fixed1
        fun wrong(k: KClass<*>): Int = k.fixed1()
        """) { path in
            let consumer = makeCompilationContext(inputs: [path], searchPaths: [directory.path], includeStdlib: false)
            try runSema(consumer)
            #expect(consumer.diagnostics.diagnostics.contains {
                $0.severity == .error && ["KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0024"].contains($0.code)
            }, "\(consumer.diagnostics.diagnostics)")
        }
    }

    @Test func invariantGenericInferenceCannotWidenArgument() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun <T : Any> KClass<T>.consume(value: T): Int = 7
        fun probe(k: KClass<Int>): Int = k.consume("wrong")
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func joiningClassLiteralsCannotManufactureInvariantAny() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun KClass<Any>.fixed(): Int = 7
        fun probe(flag: Boolean): Int = (if (flag) Int::class else String::class).fixed()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func joiningProjectedReceiverAndLiteralRetainsKClass() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun probe(flag: Boolean, k: KClass<out Int>): KClass<*> {
            val joined = if (flag) k else String::class
            return joined
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func joiningCompatibleInReceiverRetainsLowerBound() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun probe(flag: Boolean, k: KClass<in Int>): KClass<in Int> {
            val joined = if (flag) k else Any::class
            return joined
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func outReceiverPreservesCovariantGenericResult() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        class Producer<out T>
        fun <T : Any> KClass<T>.read(): Producer<T> = Producer<T>()
        fun probe(k: KClass<out Any>): Producer<Any> = k.read()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func outCaptureCannotWidenInvariantGenericResult() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        class Box<T>
        fun <T : Any> KClass<T>.boxed(): Box<T>? = null
        fun wrong(k: KClass<out Any>): Box<Any>? = k.boxed()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func outCaptureCannotConsumeThroughDependentBound() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun <T : Any, U : T> KClass<T>.consume(value: U): Int = 7
        fun wrong(k: KClass<out Any>): Int = k.consume(42)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func noStdlibAssociatedObjectStubUsesStarReceiver() throws {
        let ctx = makeKClassContext("""
        import kotlin.reflect.KClass
        fun probe(k: KClass<Int>) {}
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "reflect", "findAssociatedObject"].map(ctx.interner.intern)
        ))
        let receiver = try #require(sema.symbols.functionSignature(for: symbol)?.receiverType)
        guard case let .classType(classType) = sema.types.kind(of: receiver) else {
            Issue.record("Expected nominal star receiver")
            return
        }
        #expect(classType.args == [.star])
        #expect(sema.types.isSubtype(sema.types.makeKClassType(argument: sema.types.intType), receiver))
    }
}
