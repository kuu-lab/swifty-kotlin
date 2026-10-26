import Foundation
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct FieldAnnotationStorageTests {
    // KUU-2071: keep the issue's reproducers directly usable by the Kotlin oracle.
    static let implicit = """
    @Target(AnnotationTarget.FIELD)
    annotation class FieldMark

    interface StateHolder<S> {
        var state: S
    }

    open class Machine<S> : StateHolder<S> {
        @FieldMark
        final override var state: S

        constructor(initialState: S) {
            state = initialState
        }
    }
    """

    static let explicit = implicit.replacingOccurrences(of: "@FieldMark", with: "@field:FieldMark")

    static let fieldPresent = """
    @Target(AnnotationTarget.FIELD)
    annotation class FieldMark

    interface StateHolder<S> {
        var state: S
    }

    class Initialized<S>(initialState: S) : StateHolder<S> {
        @FieldMark
        final override var state: S = initialState
    }

    open class Unmarked<S> : StateHolder<S> {
        final override var state: S

        constructor(initialState: S) {
            state = initialState
        }
    }
    """

    static let fieldAbsent = """
    @Target(AnnotationTarget.FIELD)
    annotation class FieldMark

    interface NoField {
        @FieldMark
        val state: Int
    }

    abstract class AbstractState {
        @FieldMark
        abstract var state: Int
    }

    class ComputedState {
        @field:FieldMark
        val state: Int
            get() = 1
    }
    """

    static let accessorStorage = """
    @Target(AnnotationTarget.FIELD)
    annotation class FieldMark

    abstract class Stored {
        @FieldMark val immutable: Int
        @field:FieldMark var mutable: Int
        @FieldMark val defaultGetter: Int
            get
        @field:FieldMark var defaultSetter: Int
            private set
        @FieldMark val customGetter: Int
            get() = field
        @field:FieldMark var customSetter: Int = 0
            set(value) { field = value }
        @FieldMark var partialAccessor: Int
            get() = 1
        @field:FieldMark var bothAccessors: Int = 0
            get() = field
            set(value) { field = value }

        constructor(value: Int) {
            immutable = value
            mutable = value
            defaultGetter = value
            defaultSetter = value
            customGetter = value
            customSetter = value
            partialAccessor = value
            bothAccessors = value
        }
    }
    """

    static let fieldlessAccessors = """
    @Target(AnnotationTarget.FIELD)
    annotation class FieldMark

    interface DefaultGetter {
        @field:FieldMark val value: Int
            get() = 1
    }
    class Computed {
        @FieldMark var value: Int
            get() = 1
            set(value) {}
        @field:FieldMark val defaultSetterDoesNotAddStorage: Int
            get() = 1
    }
    @FieldMark val String.extension: Int
        get() = 1
    class Delegate {
        operator fun getValue(thisRef: Any?, property: Any?): Int = 1
    }
    class Delegated {
        @field:FieldMark val value: Int by Delegate()
    }
    """

    static let uninitialized = """
    @Target(AnnotationTarget.FIELD)
    annotation class FieldMark

    class Missing {
        @FieldMark val immutable: Int
        @field:FieldMark var mutable: Int
    }
    """

    static let shadowedField = """
    @Target(AnnotationTarget.FIELD)
    annotation class FieldMark
    class Computed {
        @FieldMark val implicit: Int
            get() { val field = 0; return field }
        @field:FieldMark val explicit: Int
            get() { val field = 0; return field }
        init {}
    }
    """

    static let localStorage = """
    class Outer {
        @Target(AnnotationTarget.FIELD)
        annotation class FieldMark
        fun check() {
            class Local {
                @field:FieldMark val state: Int
                    get() = field
                constructor(value: Int) { state = value }
            }
            Local(1)
        }
    }
    """

    @Test(arguments: [implicit, explicit, fieldPresent, accessorStorage, localStorage])
    func acceptsStoredProperties(source: String) throws {
        let context = try frontend(source)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [(fieldAbsent, 3), (fieldlessAccessors, 5), (shadowedField, 2)])
    func rejectsFieldlessProperties(probe: (String, Int)) throws {
        let context = try frontend(probe.0)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == probe.1, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }, "\(errors)")
    }

    @Test
    func fieldEligibilityDoesNotBypassInitialization() throws {
        let context = try frontend(Self.uninitialized)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0424" }, "\(errors)")
    }

    private func frontend(_ source: String) throws -> CompilationContext {
        // The annotation registry supplies Target/FIELD without bundled stdlib.
        // Source/artifact routes are checked separately by the compile-only matrix.
        let path = "/tmp/field-annotation-storage-\(UUID().uuidString).kt"
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        do {
            try runSema(context)
        } catch {
            if !context.diagnostics.hasError { throw error }
        }
        return context
    }
}
