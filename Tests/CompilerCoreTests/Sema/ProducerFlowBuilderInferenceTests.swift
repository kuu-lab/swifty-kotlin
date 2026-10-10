import Foundation
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ProducerFlowBuilderInferenceTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test(arguments: [false, true])
    func receiverMembersInferTypesAndPreserveSelectedLauncherABI(fromSource: Bool) throws {
        let source = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/kotlinx_coroutines_flow_builder_inference.kt"), encoding: .utf8)
        let context = try frontend([source, """
        package shadow
        class LocalSink<T> { fun put(value: T) {} }
        fun <T> channelFlow(block: LocalSink<T>.() -> Unit): T = null as T
        fun checkShadow() { val result = channelFlow { put(1) }; val typed: Int = result }
        fun checkQualifiedShadow() {
            val channelFlow = 0
            val result = kotlinx.coroutines.flow.channelFlow { send(9) }
            val typed: kotlinx.coroutines.flow.Flow<Int> = result
        }
        """, """
        package evidence
        class Text(val value: String)
        open class Slot<T> { fun get(): T = null as T; fun put(value: T) {} }
        class IntSlot : Slot<Int>()
        fun <T> build(block: Slot<T>.() -> Unit): T = null as T
        fun <T> concrete(block: IntSlot.(Slot<T>) -> Unit): T = null as T
        fun checkEvidence() {
            val monomorphic = build { Text(get()) }
            val string: String = monomorphic
            val inherited = concrete { this.put(it.get()) }
            val integer: Int = inherited
        }
        """, """
        package reviewed
        class Sink<T> {
            fun put(value: T) {}
            fun addAll(vararg values: T) {}
        }
        fun <T> buildSeed(seed: T, block: Sink<T>.() -> Unit): Sink<T> = Sink<T>().apply(block)
        fun <T> build(block: Sink<T>.() -> Unit): Sink<T> = Sink<T>().apply(block)
        fun checkLiteral() { val x = buildSeed<Long>(1) { put(2) }; val typed: Sink<Long> = x }
        fun checkSpread() { val x = build { addAll(*arrayOf(1, 2)) }; val typed: Sink<Int> = x }
        fun checkNamed() { val x = build { addAll(values = arrayOf(1, 2)) }; val typed: Sink<Int> = x }
        """, """
        package constructorprobe
        class Box<U>(val initial: U, block: (U) -> Unit) { init { block(initial) } }
        class Sink<T> { fun put(value: T) {} }
        fun <T> build(block: Sink<T>.() -> Unit): Sink<T> = Sink<T>().apply(block)
        fun check() { val x = build { put(1); Box(1) { v -> val typed: Int = v } }; val typed: Sink<Int> = x }
        """], fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let expected: [(String, TypeID)] = [
            ("inferredInts", sema.types.intType), ("inferredStrings", sema.types.stringType),
            ("inferredNullable", sema.types.makeNullable(sema.types.intType)),
            ("inferredQualified", sema.types.intType), ("inferredAlias", sema.types.intType),
            ("inferredCallbackAlias", sema.types.stringType), ("inferredPackage", sema.types.intType),
            ("explicitPackage", sema.types.longType),
            ("inferredLatest", sema.types.stringType), ("explicitLong", sema.types.longType),
            ("inferredSlot", sema.types.stringType), ("inferredDerived", sema.types.intType),
            ("inferredUnrelatedReceiver", sema.types.intType),
            ("inferredMember", sema.types.stringType),
        ]
        for (name, element) in expected {
            let symbol = try #require(sema.symbols.lookup(fqName: [context.interner.intern(name)]))
            let result = try #require(sema.symbols.functionSignature(for: symbol)).returnType
            guard case let .classType(nominal) = sema.types.kind(of: result) else {
                Issue.record("\(name): expected generic nominal result, got \(sema.types.renderType(result))")
                continue
            }
            #expect(nominal.args == [.invariant(element)], "\(name): \(sema.types.renderType(result))")
        }
        let ast = try #require(context.ast)
        var producerCount = 0
        var shadowCount = 0
        for (index, expression) in ast.arena.exprs.enumerated() {
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: context), let binding = sema.bindings.callBinding(for: id),
                  let chosen = sema.symbols.symbol(binding.chosenCallee)
            else { continue }
            let name = chosen.fqName.map(context.interner.resolve).joined(separator: ".")
            guard name == "kotlinx.coroutines.flow.channelFlow" || name == "kotlinx.coroutines.flow.callbackFlow"
                || name == "shadow.channelFlow"
            else { continue }
            let arguments: [CallArgument]
            switch expression {
            case let .call(_, _, args, _), let .memberCall(_, _, _, args, _): arguments = args
            default: continue
            }
            let lambda = try #require(arguments.first { ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }).expr
            if name == "shadow.channelFlow" {
                shadowCount += 1
                #expect(!sema.bindings.isCoroutineLauncherLambdaExpr(lambda))
            } else {
                producerCount += 1
                #expect(sema.bindings.isCoroutineLauncherLambdaExpr(lambda), "\(name) lost launcher slots")
            }
        }
        #expect(producerCount == 14)
        #expect(shadowCount == 1)
    }

    @Test(arguments: [false, true])
    func samePackageUserOverloadKeepsRegularReceiverABI(fromSource: Bool) throws {
        let context = try frontend(["""
        package kotlinx.coroutines.flow
        class LocalSink<T> { fun put(value: T) {} }
        fun <T> channelFlow(seed: T, block: LocalSink<T>.() -> Unit): T = seed
        """, """
        import kotlinx.coroutines.flow.channelFlow
        fun checkOverload() { val result: Int = channelFlow(1) { put(2) } }
        """], fromSource: fromSource)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        var checked = 0
        for (index, expression) in ast.arena.exprs.enumerated() {
            let id = ExprID(rawValue: Int32(index))
            guard isUserSourceExpr(id, in: context), case let .call(_, _, args, _) = expression,
                  let binding = sema.bindings.callBinding(for: id),
                  sema.symbols.symbol(binding.chosenCallee)?.name == context.interner.intern("channelFlow")
            else { continue }
            let lambda = try #require(args.first { ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }).expr
            #expect(!sema.bindings.isCoroutineLauncherLambdaExpr(lambda))
            #expect(sema.bindings.exprType(for: id) == sema.types.intType)
            checked += 1
        }
        #expect(checked == 1)
    }

    @Test(arguments: [false, true])
    func absentEvidenceAndIncompatibleValuesRemainErrors(fromSource: Bool) throws {
        let probes: [(String, String)] = [
            ("val bad = channelFlow {}", "KSWIFTK-SEMA-INFER"),
            ("val bad = kotlinx.coroutines.flow.channelFlow {}", "KSWIFTK-SEMA-INFER"),
            ("val bad = callbackFlow { close() }", "KSWIFTK-SEMA-INFER"),
            ("val bad = flowOf(1).transformLatest {}", "KSWIFTK-SEMA-INFER"),
            ("val bad = buildSlot {}", "KSWIFTK-SEMA-INFER"),
            ("val bad = buildSlot { unrelated(1) }", "KSWIFTK-SEMA-INFER"),
            ("val other = Slot<String>(); val bad = buildSlot { other.put(\"other\") }", "KSWIFTK-SEMA-INFER"),
            ("val bad = buildSlot { val other = Slot(\"other\") }", "KSWIFTK-SEMA-INFER"),
            ("val bad: Flow<Int> = channelFlow { send(\"wrong\") }", "KSWIFTK-TYPE-0001"),
            ("val bad = callbackFlow<Int> { trySend(\"wrong\"); close() }", "KSWIFTK-TYPE-0001"),
            ("val bad = kotlinx.coroutines.flow.callbackFlow<Int> { trySend(\"wrong\"); close() }", "KSWIFTK-TYPE-0001"),
            ("val bad: Flow<Int> = kotlinx.coroutines.flow.channelFlow { send(\"wrong\") }", "KSWIFTK-TYPE-0001"),
            ("val bad: Flow<Int> = channelFlow { send(null) }", "KSWIFTK-TYPE-0001"),
            ("val bad: Flow<String> = flowOf(1).transformLatest { emit(it) }", "KSWIFTK-TYPE-0001"),
            ("val bad: Slot<Int> = buildSlot { put(\"wrong\") }", "KSWIFTK-TYPE-0001"),
            ("val bad = Slot<Int>().apply { put<String>(1) }", "KSWIFTK-SEMA-0002"),
        ]
        let sources = probes.enumerated().map { index, probe in
            """
            package probe\(index)
            import kotlinx.coroutines.flow.*
            class Slot<T>(val initial: T? = null) {
                fun put(value: T) {}
                fun <U> unrelated(value: U) {}
            }
            fun <T> buildSlot(block: Slot<T>.() -> Unit): Slot<T> = Slot<T>().apply(block)
            fun bad() { \(probe.0) }
            """
        }
        let context = try frontend(sources, fromSource: fromSource)
        for (index, probe) in probes.enumerated() {
            let file = try #require(context.sourceManager.fileID(forPath: inputPath(index)))
            let body = try #require(sources[index].range(of: probe.0))
            let bodyStart = sources[index].utf8.distance(from: sources[index].utf8.startIndex, to: body.lowerBound)
            let bodyEnd = sources[index].utf8.distance(from: sources[index].utf8.startIndex, to: body.upperBound)
            #expect(context.diagnostics.diagnostics.contains {
                guard $0.severity == .error, $0.code == probe.1, let range = $0.primaryRange else { return false }
                return range.start.file == file && range.start.offset >= bodyStart && range.end.offset <= bodyEnd
            }, "\(probe.0): \(context.diagnostics.diagnostics)")
        }
    }

    private func inputPath(_ index: Int) -> String { "/tmp/producer-flow-builder-\(index).kt" }

    private func frontend(_ sources: [String], fromSource: Bool) throws -> CompilationContext {
        let inputs = sources.indices.map(inputPath)
        let stdlib: String?
        if fromSource { stdlib = nil } else {
            TestStdlibCache.shared.prepare()
            stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        return CompilerDriver().runFrontend(options: CompilerOptions(
            moduleName: "ProducerFlowBuilderInference", inputs: inputs, outputPath: "/tmp/producer-flow-builder",
            emit: .kirDump, target: defaultTargetTriple(), stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: !fromSource
        ), inMemorySources: Dictionary(uniqueKeysWithValues: zip(inputs, sources.map { Data($0.utf8) }))).context
    }
}
