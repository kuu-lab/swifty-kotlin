@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ExtensionPropertySetterAssignmentTests {
    private let declarations = """
    var <T> T.receiverCallback: T.(String) -> String
        get() = { value: String -> value }
        set(value: T.(String) -> String) {}

    var Int.plainCallback: (String) -> String
        get() = { it }
        set(value) {}

    var Number.selectedCallback: (Boolean) -> Boolean
        get() = { it }
        set(value) {}
    var Int.selectedCallback: (String) -> String
        get() = { it }
        set(value) {}
    """

    private func context(_ source: String, inputs: [String] = ["/virtual/extension-property-setter.kt"]) -> CompilationContext {
        let ctx = makeCompilationContext(inputs: inputs, includeStdlib: false)
        for (path, text) in zip(inputs, source.components(separatedBy: "\n--- FILE ---\n")) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(text.utf8))
        }
        return ctx
    }

    @Test
    func receiverFunctionLambdasAndOverloadsAreContextualized() throws {
        let ctx = context(declarations + """

        fun valid() {
            1.receiverCallback = { "OK" }
            1.receiverCallback = { value: String -> value }
            1.plainCallback = { it }

            val typed: Int.(String) -> String = { value: String -> value }
            1.receiverCallback = typed

            var local: Int.(String) -> String = { value: String -> value }
            local = { value: String -> value }

            1.selectedCallback = { value: String -> value }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func setterValueTypeAndOverloadBoundaryRejectMismatchedLambdas() throws {
        let ctx = context(declarations + """

        fun invalid() {
            1.receiverCallback = { value: Int -> value.toString() }
            1.plainCallback = { 1 }
            1.selectedCallback = { value: Boolean -> value }
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Mismatched setter lambdas must be rejected")
    }

    @Test
    func privateExtensionSetterRemainsInaccessibleFromAnotherFile() throws {
        let paths = ["/virtual/private-extension-setter.kt", "/virtual/extension-setter-consumer.kt"]
        let ctx = context("""
        var Int.privateCallback: (String) -> String
            get() = { it }
            private set(value) {}
        --- FILE ---
        fun invalid() { 1.privateCallback = { value: String -> value } }
        """, inputs: paths)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" },
            "A private extension setter must remain inaccessible across files: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func genericCallUsesExtensionSetterValueType() throws {
        let ctx = context("""
        class Box<T>
        fun <T> makeArray(): Array<T> = null as Array<T>
        var Int.items: Array<String>
            get() = makeArray()
            set(value) {}
        var String.items: Array<Int>
            get() = makeArray()
            set(value) {}
        var <T> Box<T>.items: Array<T>
            get() = makeArray()
            set(value) {}
        var <T> T.receiverItems: Array<T>
            get() = makeArray()
            set(value) {}
        var Number.selectedItems: Array<Int>
            get() = makeArray()
            set(value) {}
        var Int.selectedItems: Array<String>
            get() = makeArray()
            set(value) {}

        fun valid(box: Box<String>) {
            1.items = makeArray()
            "text".items = makeArray()
            box.items = makeArray()
            "text".receiverItems = makeArray()
            1.selectedItems = makeArray()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func contextualGenericCallDoesNotHideSetterAmbiguityOrTypeMismatch() throws {
        let ctx = context("""
        interface A
        interface B
        class Both : A, B
        fun <T> makeArray(): Array<T> = null as Array<T>
        var A.items: Array<String>
            get() = makeArray()
            set(value) {}
        var B.items: Array<String>
            get() = makeArray()
            set(value) {}
        fun ambiguous(receiver: Both) { receiver.items = makeArray() }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" },
                "Expected an ambiguous setter: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func incompatibleExplicitGenericSetterValueIsRejected() throws {
        let ctx = context("""
        fun <T> makeArray(): Array<T> = null as Array<T>
        var Int.names: Array<String>
            get() = makeArray()
            set(value) {}
        fun wrongType() { 1.names = makeArray<Int>() }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "An incompatible setter value must be rejected")
    }

    @Test
    func genericSetterValueDoesNotBypassPrivateSetter() throws {
        let paths = ["/virtual/private-extension-setter.kt", "/virtual/extension-setter-consumer.kt"]
        let ctx = context("""
        fun <T> makeArray(): Array<T> = null as Array<T>
        var Int.privateNames: Array<String>
            get() = makeArray()
            private set(value) {}
        --- FILE ---
        fun invalid() { 1.privateNames = makeArray() }
        """, inputs: paths)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" },
                "A private extension setter must remain inaccessible: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func inaccessibleSpecificSetterCannotFallBackToBroaderReceiver() throws {
        let paths = ["/virtual/private-specific-setter.kt", "/virtual/extension-setter-consumer.kt"]
        let ctx = context("""
        fun <T> makeArray(): Array<T> = null as Array<T>
        var Number.names: Array<Int>
            get() = makeArray()
            set(value) {}
        var Int.names: Array<String>
            get() = makeArray()
            private set(value) {}
        --- FILE ---
        fun invalid() { 1.names = makeArray() }
        """, inputs: paths)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" },
                "An inaccessible specific setter must not fall back: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func memberExtensionSetterRequiresItsDispatchReceiver() throws {
        let ctx = context("""
        fun <T> makeArray(): Array<T> = null as Array<T>
        class Owner {
            var Int.memberItems: Array<String>
                get() = makeArray()
                set(value) {}
        }
        fun invalid() { 1.memberItems = makeArray() }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A member extension requires its enclosing receiver")
    }

    @Test
    func memberExtensionSetterUsesItsEnclosingReceiver() throws {
        let ctx = context("""
        fun <T> makeArray(): Array<T> = null as Array<T>
        class Owner {
            var Int.memberItems: Array<String>
                get() = makeArray()
                set(value) {}
            fun valid() { 1.memberItems = makeArray() }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func importedObjectMemberExtensionSetterUsesItsObjectReceiver() throws {
        let ctx = context("""
        import Holder.items
        fun <T> makeArray(): Array<T> = null as Array<T>
        object Holder {
            var Int.items: Array<String>
                get() = makeArray()
                set(value) {}
        }
        fun valid() { 1.items = makeArray() }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func genericMemberExtensionSetterUsesDispatchReceiverTypeParameter() throws {
        let ctx = context("""
        fun <T> makeArray(): Array<T> = null as Array<T>
        class Owner<T> {
            var Int.items: Array<T>
                get() = makeArray()
                set(value) {}
            fun valid() { 1.items = makeArray() }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
