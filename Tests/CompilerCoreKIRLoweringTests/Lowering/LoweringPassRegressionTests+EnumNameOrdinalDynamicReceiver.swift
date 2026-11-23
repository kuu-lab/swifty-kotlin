#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    @Test
    func testGenericEnumPropertiesBypassStoredFieldReads() throws {
        let source = """
        fun <T : Enum<T>> enumName(value: T): String = value.name
        fun <T : Enum<T>> enumOrdinal(value: T): Int = value.ordinal
        fun <T : Enum<T>> T.implicitName(): String = name
        fun baseName(value: Enum<*>): String = value.name
        enum class E { A, B }
        fun concreteName(value: E): String = value.name
        fun concreteOrdinal(value: E): Int = value.ordinal
        fun main() { println(enumName(E.A)) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "GenericEnumProperties", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            let module = try #require(ctx.kir)
            for name in ["enumName", "implicitName", "baseName", "enumOrdinal"] {
                let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(!callees.contains(RuntimeCall.arrayGetInbounds.name))
                #expect(callees.contains(name == "enumOrdinal" ? RuntimeCall.unboxInt.name : "__kk_enum_name"))
            }
            let concreteName = try findKIRFunctionBody(named: "concreteName", in: module, interner: ctx.interner)
            #expect(extractCallees(from: concreteName, interner: ctx.interner).contains {
                $0.hasPrefix("$enumOrdinalToName$")
            })
            let concreteOrdinal = try findKIRFunctionBody(named: "concreteOrdinal", in: module, interner: ctx.interner)
            #expect(extractCallees(from: concreteOrdinal, interner: ctx.interner).contains(RuntimeCall.unboxInt.name))
        }
    }

    @Test
    func testEnumNameOnFunctionParameterLowersToHelperCallWithReceiver() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun printName(d: Direction) {
            println(d.name)
        }
        fun main() {
            printName(Direction.NORTH)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameDynamicParam", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "printName", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(!callees.contains("name"),
                    "the raw unresolved \"name\" call must be rewritten away; callees: \(callees)")
            #expect(callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "expected a rewrite to $enumOrdinalToName$<id>; callees: \(callees)")

            let helperCalls = body.compactMap { instruction -> Int? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee).hasPrefix("$enumOrdinalToName$")
                else { return nil }
                return arguments.count
            }
            #expect(helperCalls == [1], "the receiver must survive as the helper's sole argument; got: \(helperCalls)")
        }
    }

    @Test
    func testEnumOrdinalOnFunctionParameterLowersToUnboxCallWithReceiver() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun printOrdinal(d: Direction) {
            println(d.ordinal)
        }
        fun main() {
            printOrdinal(Direction.SOUTH)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumOrdinalDynamicParam", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "printOrdinal", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(!callees.contains("ordinal"),
                    "the raw unresolved \"ordinal\" call must be rewritten away; callees: \(callees)")

            let unboxCalls = body.compactMap { instruction -> Int? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      callee == ctx.interner.intern(RuntimeCall.unboxInt.name)
                else { return nil }
                return arguments.count
            }
            #expect(unboxCalls == [1], "expected a single kk_unbox_int(receiver) call; got: \(unboxCalls)")
        }
    }

    @Test
    func testEnumNameOnCollectionHOFLambdaParameterLowersToHelperCall() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun main() {
            listOf(Direction.NORTH, Direction.SOUTH).forEach { d -> println(d.name) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameHOFLambdaParam", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            #expect(!allCallees.contains("name"),
                    "the raw unresolved \"name\" call must be rewritten away; callees: \(allCallees)")
            #expect(allCallees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "expected a rewrite to $enumOrdinalToName$<id>; callees: \(allCallees)")
        }
    }

    @Test
    func testEnumNameOnLiteralEntryReceiverStaysOnFastPath() throws {
        let source = """
        enum class Direction { NORTH, SOUTH }
        fun main() {
            println(Direction.NORTH.name)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameLiteralConstFold", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            let sema = try #require(ctx.sema)
            let northSymbol = try #require(sema.symbols.allSymbols().first {
                $0.kind == .field && $0.name == ctx.interner.intern("NORTH")
            })
            let northNameHelper = ctx.interner.resolve(
                NameMangler.enumEntryNameHelperName(for: northSymbol, interner: ctx.interner)
            )

            #expect(!callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "a literal entry receiver should stay on the per-entry helper fast path; callees: \(callees)")
            #expect(!callees.contains("name"), "callees: \(callees)")
            #expect(callees.contains(northNameHelper),
                    "expected the literal fast path's per-entry helper call; callees: \(callees)")

            let nameHelperBody = try findKIRFunctionBody(named: northNameHelper, in: module, interner: ctx.interner)
            let stringLiterals = nameHelperBody.compactMap { instruction -> String? in
                guard case let .constValue(_, value) = instruction, case let .stringLiteral(s) = value else { return nil }
                return ctx.interner.resolve(s)
            }
            #expect(stringLiterals.contains("NORTH"), "expected \(northNameHelper) to return the \"NORTH\" literal; got: \(stringLiterals)")
        }
    }

    @Test
    func testEnumNameOnLiteralEntryDoesNotTriggerLazyInit() throws {
        let source = """
        var result = "OK"
        enum class E { OK; init { result = "Fail" } }
        fun box() = if (E.OK.name != "OK") "Fail 1" else result
        fun main() { println(box()) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameNoInit", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let boxBody = try findKIRFunctionBody(named: "box", in: module, interner: ctx.interner)
            let callees = extractCallees(from: boxBody, interner: ctx.interner)

            #expect(!callees.contains("$enumEnsureInit$"),
                    "E.OK.name folds to a constant; the enum's init must not run; callees: \(callees)")

            let sema = try #require(ctx.sema)
            let entrySymbol = try #require(sema.symbols.allSymbols().first {
                $0.kind == .field && $0.name == ctx.interner.intern("OK")
            })
            #expect(!boxBody.contains { instruction in
                switch instruction {
                case let .constValue(_, .symbolRef(symbol)),
                     let .loadGlobal(_, symbol):
                    symbol == entrySymbol.id
                default:
                    false
                }
            }, "the dead entry materialization should have been folded away")

            #expect(callees.contains(where: { $0.contains("$enumName$") }),
                    "expected the per-entry name helper call; callees: \(callees)")
        }
    }

    // Unlike `.name`, kotlinc does NOT const-fold `E.OK.ordinal`: the entry
    // load still happens, so `<clinit>` must run. Guard against an
    // over-eager fold that would diverge from the JVM.
    @Test
    func testEnumOrdinalOnLiteralEntryStillTriggersLazyInit() throws {
        let source = """
        var result = "OK"
        enum class E { OK; init { result = "Fail" } }
        fun box() = if (E.OK.ordinal != 0) "Fail 1" else result
        fun main() { println(box()) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumOrdinalKeepsInit", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let boxBody = try findKIRFunctionBody(named: "box", in: module, interner: ctx.interner)
            let callees = extractCallees(from: boxBody, interner: ctx.interner)
            #expect(callees.contains("$enumEnsureInit$"),
                    "E.OK.ordinal still loads the entry on the JVM; the enum's init must run; callees: \(callees)")
        }
    }

    @Test
    func testEnumEntryLocalReadStillTriggersLazyInit() throws {
        let source = """
        var result = "OK"
        enum class E { OK; init { result = "Fail" } }
        fun box(): String {
            val e = E.OK
            return if (e.name != "OK") "Fail 1" else result
        }
        fun main() { println(box()) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumLocalEntryInit", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let boxBody = try findKIRFunctionBody(named: "box", in: module, interner: ctx.interner)
            let callees = extractCallees(from: boxBody, interner: ctx.interner)
            #expect(callees.contains("$enumEnsureInit$"),
                    "val e = E.OK is a real entry load; the enum's init must still run; callees: \(callees)")
        }
    }

    @Test
    func testEnumNameOnImplicitReceiverLowersToHelperCallWithReceiver() throws {
        let source = """
        enum class Dir { N, S; fun greet() = name.lowercase() }
        fun main() {
            println(Dir.N.greet())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumNameImplicitReceiver", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "greet", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(!callees.contains("name"),
                    "the raw unresolved \"name\" call must be rewritten away; callees: \(callees)")
            #expect(callees.contains(where: { $0.hasPrefix("$enumOrdinalToName$") }),
                    "expected a rewrite to $enumOrdinalToName$<id>; callees: \(callees)")
        }
    }

    @Test
    func testEnumOrdinalOnImplicitReceiverLowersToUnboxCall() throws {
        let source = """
        enum class Dir { N, S; fun index() = ordinal }
        fun main() {
            println(Dir.S.index())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumOrdinalImplicitReceiver", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "index", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(!callees.contains("ordinal"),
                    "the raw unresolved \"ordinal\" call must be rewritten away; callees: \(callees)")
            #expect(callees.contains(RuntimeCall.unboxInt.name),
                    "expected the implicit receiver to be unboxed; callees: \(callees)")
        }
    }

    @Test
    func testEnumConstructorPropertyOnImplicitReceiverLowersToHelperCall() throws {
        let source = """
        enum class Color(val rgb: Int) {
            RED(0xFF0000), GREEN(0x00FF00), BLUE(0x0000FF);
            fun hex() = rgb.toString(16)
        }
        fun main() {
            println(Color.RED.hex())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "EnumConstructorPropertyImplicitReceiver", emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "hex", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains(where: { $0.hasPrefix("$enumConstructorProperty$") }),
                    "expected a rewrite to the $enumConstructorProperty$ helper; callees: \(callees)")
        }
    }
}
#endif
