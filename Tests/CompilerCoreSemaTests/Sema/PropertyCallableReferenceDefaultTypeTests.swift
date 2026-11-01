#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

/// KSP-496 follow-up: `inferCallableRefExpr` (`ExprTypeChecker+NameLambdaAndCallableRefInference.swift`)
/// used to fall back to the property's own *value* type when a property
/// callable reference (`Type::property`, `instance::property`, or bare
/// `::property`) had no expected type to adopt — e.g. `val ref = C::v` was
/// typed as `Int` instead of `KProperty1<C, Int>`. Since the KIR wrapper that
/// makes `is KProperty<*>` etc. work is only emitted when the bound type is
/// literally `KProperty0`/`KMutableProperty0`/`KProperty1`/`KMutableProperty1`
/// (see `LambdaLowerer+PropertyReferenceLowering.swift`), this silently
/// produced wrong values at runtime (observed: `println(C::v)` printed `0`).
///
/// These tests fix the Sema-level regression: a property callable reference
/// must infer to a real `KPropertyN`/`KMutablePropertyN` type even without an
/// expected type context, matching what `Type::method` already does for
/// function references.
@Suite
struct PropertyCallableReferenceDefaultTypeTests {
    @Test func nullableExtensionPropertyReferences() throws {
        let ctx = makeContextFromSource("""
        class A
        val A?.foo: String get() = "O"
        var <T> T.bar: T get() = this; set(v) {}
        fun test() {
            val ref = A?::foo
            val value: String = ref(null)
            String?::bar.set(null, null)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
    }

    private func classTypeSymbol(
        for exprID: ExprID,
        sema: SemaModule
    ) throws -> (symbol: SemanticSymbol, args: [TypeArg]) {
        let exprType = try #require(sema.bindings.exprTypes[exprID])
        guard case let .classType(classType) = sema.types.kind(of: exprType) else {
            Issue.record("Expected a class type for the callable reference, got \(sema.types.kind(of: exprType))")
            throw TestFailure.unexpectedShape
        }
        let symbol = try #require(sema.symbols.symbol(classType.classSymbol))
        return (symbol, classType.args)
    }

    private enum TestFailure: Error { case unexpectedShape }

    @Test func testUnboundImmutablePropertyReferenceInfersKProperty1WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        class C(val v: Int)
        fun main() {
            val ref = C::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, args) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty1"],
            "C::v without an expected type should infer KProperty1<C, Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
        #expect(args.count == 2, "KProperty1 takes two type arguments (owner, value).")
    }

    @Test func testClassNameCompanionPropertyReferenceInfersKProperty0() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KProperty0
        class Sample { companion object { const val value = 1 } }
        fun take(property: KProperty0<Int>): Int = property.get()
        fun main() { take(Sample::value) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reference = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let (symbol, args) = try classTypeSymbol(for: reference, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty0"],
            "Sample::value is owned by the companion and should infer KProperty0<Int>"
        )
        #expect(args == [.invariant(sema.types.intType)])
        #expect(!sema.bindings.isUnboundCallableRef(reference))
    }

    @Test func classNameReferenceToMissingCompanionPropertyRemainsUnresolved() throws {
        let ctx = makeContextFromSource("""
        class Sample { companion object { const val value = 1 } }
        fun main() { val ref = Sample::missing }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error
                && $0.code == "KSWIFTK-SEMA-0022"
                && $0.message == "Unresolved reference '::missing'."
        })
    }

    @Test func testInheritedGenericPropertyReferenceSubstitutesValueType() throws {
        let ctx = makeContextFromSource("""
        open class Parent<T>(val value: T)
        class Child<T>(value: T) : Parent<T>(value)
        fun main() {
            val ref = Child<Int>::value
            val value: Int = ref.get(Child(42))
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.isEmpty, "Unexpected diagnostics: \(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let (symbol, args) = try classTypeSymbol(for: ref, sema: sema)
        #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty1"])
        try #require(args.count == 2)
        #expect(args[1] == .invariant(sema.types.intType))
        guard case let .invariant(ownerType) = args[0],
              case let .classType(owner) = sema.types.kind(of: ownerType) else {
            Issue.record("Expected a concrete receiver type")
            return
        }
        #expect(sema.symbols.symbol(owner.classSymbol)?.name == ctx.interner.intern("Child"))
        #expect(owner.args == [.invariant(sema.types.intType)])
        #expect(!sema.types.typeContainsAnyTypeParam(try #require(sema.bindings.exprTypes[ref])))
    }

    @Test func testBoundImmutablePropertyReferenceInfersKProperty0WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        class C(val v: Int)
        fun main(c: C) {
            val ref = c::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, args) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty0"],
            "c::v without an expected type should infer KProperty0<Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
        #expect(args.count == 1, "KProperty0 takes one type argument (value).")
    }

    @Test func testBoundGenericMemberPropertyReferenceSpecializesCapturedReceiverType() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun box(): String {
            var methodVar = "OK"

            fun localMethod(): String {
                return lazy { methodVar }::value.get()
            }

            return localMethod()
        }

        fun minimized(): String = lazy { "OK" }::value.get()
        fun directRead(): String = lazy { "OK" }.value

        class ConcreteBox(val value: String)
        fun nonGenericBoundReference(): String = ConcreteBox("OK")::value.get()
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let inputPath = try #require(ctx.options.inputs.first)
        let inputFileID = try #require(ctx.sourceManager.fileID(forPath: inputPath))
        let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case .callableRef = expr,
                  ast.arena.exprRange(exprID)?.start.file == inputFileID
            else { return nil }
            return exprID
        }
        try #require(references.count == 3)

        for reference in references {
            let (symbol, args) = try classTypeSymbol(for: reference, sema: sema)
            #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty0"])
            try #require(args.count == 1)
            #expect(args[0] == .invariant(sema.types.stringType))
            #expect(!sema.types.typeContainsAnyTypeParam(try #require(sema.bindings.exprTypes[reference])))
        }
    }

    @Test(arguments: [
        "val ref: KProperty0<Int> = Box(\"OK\")::value",
        "val ref: KProperty1<Box<String>, String> = Box(\"OK\")::value",
    ])
    func rejectsIncompatibleBoundGenericPropertyReference(declaration: String) throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KProperty0
        import kotlin.reflect.KProperty1
        class Box<T>(val value: T)
        fun main() { \(declaration) }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0468"
        })
    }

    @Test func testUnboundMutablePropertyReferenceInfersKMutableProperty1WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        class C(var v: Int)
        fun main() {
            val ref = C::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, _) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KMutableProperty1"],
            "C::v of a `var` property without an expected type should infer KMutableProperty1<C, Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
    }

    @Test func testBareTopLevelPropertyReferenceInfersKProperty0WithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        val answer: Int = 42
        fun main() {
            val ref = ::answer
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, args) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(
            symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty0"],
            "::answer without an expected type should infer KProperty0<Int>, got fqName \(symbol.fqName.map { ctx.interner.resolve($0) })"
        )
        #expect(args.count == 1, "KProperty0 takes one type argument (value).")
    }

    /// An explicit expected type must still win over the default (unchanged
    /// pre-existing behavior — this test just pins it so a future change to
    /// the default-inference path doesn't accidentally start overriding it).
    @Test func testExplicitExpectedTypeStillWinsOverDefaultInference() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KProperty1
        class C(val v: Int)
        fun main() {
            val ref: KProperty1<C, Int> = C::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let (symbol, _) = try classTypeSymbol(for: callableRefExprID, sema: sema)
        #expect(symbol.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "reflect", "KProperty1"])
    }

    /// A property reference is also a valid function value in Kotlin
    /// (`val f: (C) -> Int = C::v`, `list.map(C::v)`), so a function-typed
    /// expected type must still be honored as-is — the same as before this
    /// fix — rather than being overridden by the newly-inferred KPropertyN
    /// default. This only pins the Sema-level type binding: whether the
    /// resulting KIR/codegen path for a property reference bound to an
    /// explicit function type actually links and runs correctly is tracked
    /// separately in TODO.md (a pre-existing, unrelated bug — reproducible
    /// on stock master with no dependency on this fix).
    @Test func testExplicitFunctionTypeExpectedTypeStillWinsOverKPropertyDefault() throws {
        let ctx = makeContextFromSource("""
        class C(val v: Int)
        fun main() {
            val f: (C) -> Int = C::v
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Expected clean compile, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callableRefExprID = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })

        let exprType = try #require(sema.bindings.exprTypes[callableRefExprID])
        guard case .functionType = sema.types.kind(of: exprType) else {
            Issue.record("Expected C::v bound to (C) -> Int to keep a function type, got \(sema.types.kind(of: exprType))")
            return
        }
    }
}
#endif
