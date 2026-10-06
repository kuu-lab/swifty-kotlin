#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TypeParameterUpperBoundArgumentTests {
    @Test func nestedBoundArgumentsAndReifiedSmartCasts() throws {
        let source = """
        import kotlinx.atomicfu.*
        import kotlin.coroutines.*

        class Ch {
            private sealed interface Slot {
                data object Empty : Slot
                data class Closed(val cause: Throwable?) : Slot
                sealed interface Task : Slot {
                    val continuation: Continuation<Unit>
                    fun resume()
                }
            }
            private val suspensionSlot: AtomicRef<Slot> = atomic(Slot.Empty)

            private inline fun <reified TaskType : Slot.Task> trySuspend(slot: TaskType) {
                val previous = suspensionSlot.value
                if (previous !is Slot.Closed) {
                    if (!suspensionSlot.compareAndSet(previous, slot)) { slot.resume() }
                }
            }

            private inline fun <reified Expected : Slot.Task> tryResume() {
                val current = suspensionSlot.value
                if (current is Expected && suspensionSlot.compareAndSet(current, Slot.Empty)) {
                    current.resume()
                }
            }
        }
        """
        // atomicfu is an external dependency; retain its invariant call contract.
        let atomicfu = """
        package kotlinx.atomicfu
        class AtomicRef<T>(var value: T) {
            fun compareAndSet(expect: T, update: T): Boolean {
                if (value !== expect) return false
                value = update
                return true
            }
        }
        fun <T> atomic(value: T): AtomicRef<T> = AtomicRef(value)
        """
        try withTemporaryFiles(contents: [atomicfu, source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let task = try #require(sema.symbols.lookup(fqName: ["Ch", "Slot", "Task"].map(ctx.interner.intern)))
            let taskType = sema.types.make(.classType(ClassType(classSymbol: task)))
            for name in ["trySuspend", "tryResume"] {
                let function = try #require(sema.symbols.lookup(fqName: ["Ch", name].map(ctx.interner.intern)))
                let signature = try #require(sema.symbols.functionSignature(for: function))
                let parameter = try #require(signature.typeParameterSymbols.first)
                #expect(sema.symbols.typeParameterUpperBounds(for: parameter) == [taskType])
            }
        }
    }

    @Test(arguments: [false, true])
    func ordinaryParameterAcceptsNestedUpperBound(reified: Bool) throws {
        let modifiers = reified ? "inline" : ""
        let parameter = reified ? "reified T" : "T"
        let source = """
        package sample
        interface Slot
        class Host {
            interface Slot {
                interface Task : Slot
            }
            fun accept(value: Slot) {}
            \(modifiers) fun <\(parameter) : Slot.Task> forward(value: T) { accept(value) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let function = try #require(sema.symbols.lookup(fqName: ["sample", "Host", "forward"].map(ctx.interner.intern)))
            let signature = try #require(sema.symbols.functionSignature(for: function))
            let parameter = try #require(signature.typeParameterSymbols.first)
            let bound = try #require(sema.symbols.typeParameterUpperBounds(for: parameter).first)
            guard case let .classType(type) = sema.types.kind(of: bound) else {
                Issue.record("Expected a resolved nominal upper bound")
                return
            }
            #expect(sema.symbols.symbol(type.classSymbol)?.fqName == ["sample", "Host", "Slot", "Task"].map(ctx.interner.intern))
        }
    }

    @Test func functionBoundsResolveImportAliases() throws {
        let sources = [
            "package bounds; interface Base",
            """
            package sample
            import bounds.Base as Limit
            fun accept(value: Limit) {}
            fun <T : Limit> forward(value: T) { accept(value) }
            class Host {
                fun <T : Limit> forward(value: T) { accept(value) }
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let base = try #require(sema.symbols.lookup(fqName: ["bounds", "Base"].map(ctx.interner.intern)))
            let baseType = sema.types.make(.classType(ClassType(classSymbol: base)))
            for names in [["sample", "forward"], ["sample", "Host", "forward"]] {
                let function = try #require(sema.symbols.lookup(fqName: names.map(ctx.interner.intern)))
                let signature = try #require(sema.symbols.functionSignature(for: function))
                let parameter = try #require(signature.typeParameterSymbols.first)
                #expect(sema.symbols.typeParameterUpperBounds(for: parameter) == [baseType])
            }
        }
    }

    @Test func upperBoundDoesNotAllowUnrelatedParameter() throws {
        let source = """
        interface Other
        class Host {
            interface Slot { interface Task : Slot }
            fun accept(value: Other) {}
            fun <T : Host.Slot.Task> forward(value: T) { accept(value) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        }
    }
}
#endif
