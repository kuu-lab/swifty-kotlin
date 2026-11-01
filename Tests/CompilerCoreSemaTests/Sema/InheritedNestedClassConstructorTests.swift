#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct InheritedNestedClassConstructorTests {
    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], includeStdlib: false,
            stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [false, true])
    func inheritedConstructorsUseNormalOverloadAndShadowingRules(library: Bool) throws {
        let source = """
        class NumberArg
        class TextArg
        class CurrentArg
        class LocalArg

        open class Base {
            class Packet(val value: NumberArg) {
                constructor(value: TextArg) : this(NumberArg())
            }
        }

        class Child : Base() {
            fun fromNumber(): Packet = Packet(NumberArg())
            fun fromText(): Packet = Packet(TextArg())
            fun qualified(): Base.Packet = Base.Packet(NumberArg())
        }

        class CurrentShadow : Base() {
            class Packet(val value: CurrentArg)
            fun create(): Packet = Packet(CurrentArg())
        }

        class LocalShadow : Base() {
            fun create() {
                class Packet(val value: LocalArg)
                Packet(LocalArg())
            }
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // KUU-3574: an inner constructor inherits its outer type from the current
    // subclass's generic supertype, even when the nullable argument is null.
    @Test
    func innerConstructorUsesOuterTypeArgumentFromGenericSuperclass() throws {
        let ctx = try context("""
        open class C<T> {
            inner class A<U>(val x: T?, val y: U)
            class D : C<Nothing>() {
                fun f() = A<String>(null, "OK")
            }
        }
        """, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func inheritedInterfaceDoesNotHideOuterConstructor(library: Bool) throws {
        let source = """
        interface Base {
            interface Entry {
                companion object { operator fun invoke(value: String): String = value }
            }
        }
        class Entry(val text: String)
        class Child : Base {
            fun construct(): String = Entry("outer").text
        }
        open class PrivateBase { private interface Hidden }
        class Hidden(val text: String)
        class PrivateChild : PrivateBase() {
            fun construct(): String = Hidden("outer").text
        }
        open class ProtectedBase { protected interface Marker }
        class Marker(val text: String)
        class ProtectedChild : ProtectedBase() {
            fun construct(): String = Marker("outer").text
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func inheritedClassConstructorKeepsPriorityOverOuterConstructor(library: Bool) throws {
        let source = """
        open class Base { class Entry(val inner: Int) }
        class Entry(val outer: Int)
        class Child : Base() {
            fun construct(): Int = Entry(1).inner
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func inheritedInterfaceAloneIsNotAConstructor(library: Bool) throws {
        let source = """
        interface Base { interface Entry }
        class Child : Base { fun construct() = Entry("missing") }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    @Test
    func inheritedInterfaceFallbackKeepsExplicitImportPriority() throws {
        let declaration = """
        package imported
        class Selected(val text: String)
        """
        let usage = """
        package app
        import imported.Selected as Entry
        class Entry(val number: Int)
        interface Base { interface Entry }
        class Child : Base { fun construct(): String = Entry("import").text }
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func inheritedInterfaceFallbackDoesNotExposePrivateOuterConstructor() throws {
        let declaration = """
        package scope
        private class Entry(val text: String)
        """
        let usage = """
        package scope
        interface Base { interface Entry }
        class Child : Base { fun construct() = Entry("hidden") }
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
        }
    }

    @Test
    func outerConstructorsAreConsideredWhenInheritedNestedCandidatesFail() throws {
        let source = """
        open class ConcreteBase { class Entry(val number: Int) }
        class Entry(val text: String) {
            constructor(value: Int) : this("outer $value")
        }
        class ConcreteChild : ConcreteBase() {
            fun value(): String = Entry("outer").text
            fun inherited(): ConcreteBase.Entry = Entry(1)
            fun qualified(): ConcreteBase.Entry = ConcreteBase.Entry(2)
        }

        abstract class AbstractBase { abstract class Entry(val number: Int) }
        class AbstractChild : AbstractBase() {
            fun value(): String = Entry("abstract fallback").text
        }

        open class PrivateBase { private class Entry(val number: Int) }
        class PrivateChild : PrivateBase() {
            fun value(): String = Entry("private fallback").text
        }

        class Outer {
            class Entry(val text: String)
            open class NestedBase { class Entry(val number: Int) }
            class NestedChild : NestedBase() {
                fun value(): String = Entry("lexical fallback").text
            }
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func inheritedConstructorAmbiguityDoesNotFallBackToOuterClassifier() throws {
        let source = """
        interface Left
        interface Right
        class Both : Left, Right

        open class Base {
            class Entry {
                constructor(value: Left)
                constructor(value: Right)
            }
        }
        class Entry(val text: String)
        class Child : Base() {
            fun value(input: Both) = Entry(input)
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0003", "\(errors)")
    }

    @Test
    func missingConstructorNameRemainsUnresolved() throws {
        let source = """
        open class Base { class Entry(val number: Int) }
        class Entry(val text: String)
        class Child : Base() {
            fun value() = MissingEntry(1)
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test
    func protectedInheritedNestedConstructorIsVisibleOnlyToSubclass() throws {
        let source = """
        open class Base {
            protected class Marker(val value: Int)
        }

        class Child : Base() {
            fun create(): Int = Marker(1).value
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unrelatedClassCannotCallProtectedInheritedNestedConstructor() throws {
        let source = """
        open class Base {
            protected class Marker(val value: Int)
        }

        class Unrelated {
            fun create(): Int = Marker(1).value
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    @Test
    func explicitProtectedNestedConstructorRemainsInaccessible() throws {
        let source = """
        open class Owner {
            data class Explicit protected constructor(val value: Int)
            fun fromOwner(): Int = Explicit(1).value
        }

        class OwnerChild : Owner() {
            fun fromSubclass(): Int = Owner.Explicit(2).value
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        let protectedErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0041"
        }
        #expect(protectedErrors.count == 2, "\(protectedErrors)")
    }

    // KUU-3858: an inner class on an implicit receiver is callable by its
    // simple name — the receiver supplies the enclosing instance. kotlinc
    // accepts `I()` inside `fun Outer.extSub()` exactly like `this.I()`.
    @Test
    func innerConstructorCallableByBareNameInExtensionFunction() throws {
        let source = """
        open class Outer { open inner class I }
        fun Outer.extSub() {
            val x = I()
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func innerConstructorCallableThroughInheritedExtensionReceiver() throws {
        let source = """
        open class Outer { open inner class I }
        class Sub : Outer()
        fun Sub.extSub() {
            val x = I()
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nonInnerNestedConstructorStaysUnresolvedInExtensionFunction() throws {
        let source = """
        open class Outer { open class Nested }
        fun Outer.extSub() {
            val x = Nested()
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    @Test
    func unrelatedExtensionReceiverLeavesInnerConstructorUnresolved() throws {
        let source = """
        open class Outer { open inner class I }
        class Other
        fun Other.extSub() {
            val x = I()
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    @Test
    func qualifiedInnerConstructorStillRequiresReceiverInExtension() throws {
        let source = """
        open class Outer { open inner class I }
        fun Outer.extSub() {
            val x = Outer.I()
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0437" })
    }

    @Test
    func lambdaInsideExtensionFunctionStillCallsInnerConstructor() throws {
        let source = """
        open class Outer { open inner class I }
        fun Outer.extSub() {
            val f = { I() }
        }
        """
        let ctx = try context(source, library: false)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // KUU-3798: a `private` nested classifier on a supertype is not inherited,
    // so it must not shadow a lexically enclosing declaration of the same
    // name. Mirrors kotlinx.collections.immutable's ImmutableList.SubList,
    // whose self-constructor call lost to `private AbstractList.SubList`.
    @Test(arguments: [false, true])
    func privateSupertypeNestedClassifierDoesNotShadowLexicalClassifier(library: Bool) throws {
        let source = """
        open class Base { private class Same(val number: Int) }
        interface Host<out E> {
            fun mk(n: Int): Host<E> = Same(n)
            private class Same<E>(val number: Int) : Host<E>, Base() {
                fun dup(): Host<E> = Same(number)
            }
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // KUU-3798: when the only `Same`-named classifier anywhere is a
    // supertype's private nested one, the reference still resolves to it —
    // reported as inaccessible rather than unresolved, matching kotlinc.
    @Test(arguments: [false, true])
    func privateSupertypeNestedClassifierStillReportsInaccessible(library: Bool) throws {
        let source = """
        open class Base { private class Hidden(val number: Int) }
        class Child : Base() {
            fun use() = Hidden(1)
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0023" })
    }

    // KUU-3798: the same rule applies to bare classifier references — a
    // supertype's private nested classifier is invisible but must not shadow
    // the enclosing declaration either.
    @Test(arguments: [false, true])
    func privateSupertypeNestedClassifierDoesNotShadowLexicalValue(library: Bool) throws {
        let source = """
        open class Base { private class Hidden(val number: Int) }
        class Outer {
            private class Hidden(val text: String)
            class Child : Base() {
                fun value(): String = Hidden("lexical").text
            }
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // KUU-3927: same rule, non-generic shape — the ticket's minimal repro.
    // A `private` nested class inside an interface calls its own
    // zero-argument constructor and names itself in a type position; both
    // must resolve to the class itself / the enclosing declaration, not the
    // supertype's private same-named nested classifier.
    @Test(arguments: [false, true])
    func privateSupertypeNestedClassifierDoesNotShadowNonGenericSelfClassifier(library: Bool) throws {
        let source = """
        abstract class Base {
            private class Sub
        }

        interface I {
            fun f(): I = Sub()
            private class Sub : Base(), I {
                fun g(): I = Sub()
                fun h(): Sub = Sub()
            }
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // KUU-3927: the upstream trigger — kotlinx.collections.immutable's
    // `ImmutableList.SubList` (ImmutableList.kt:54). A private nested class
    // inside an interface extends the bundled `AbstractList`, which has its
    // own `private class SubList`, and overrides the real `List.subList`
    // while calling its own constructor. `SubList` must resolve to the
    // class itself in both source-injected and artifact stdlib modes.
    @Test(arguments: [false, true])
    func privateNestedClassifierOverridingStdlibSubListCallsOwnConstructor(useLibrary: Bool) throws {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        interface ImmutableList<out E> : List<E> {
            override fun subList(fromIndex: Int, toIndex: Int): ImmutableList<E> =
                SubList(this, fromIndex, toIndex)

            private class SubList<E>(
                private val source: ImmutableList<E>,
                private val fromIndex: Int,
                private val toIndex: Int
            ) : ImmutableList<E>, AbstractList<E>() {
                private var _size: Int = toIndex - fromIndex

                override fun get(index: Int): E {
                    if (index < 0 || index >= _size) throw IndexOutOfBoundsException("index")
                    return source[fromIndex + index]
                }

                override val size: Int get() = _size

                override fun subList(fromIndex: Int, toIndex: Int): ImmutableList<E> =
                    SubList(source, this.fromIndex + fromIndex, this.fromIndex + toIndex)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let libraryPath = useLibrary ? CompilerOptions.defaultStdlibLibraryPath : nil
            let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: libraryPath)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
