#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CompilerPluginLombokTests {
    private let lombokStubs = """
    package lombok

    enum class AccessLevel {
        PUBLIC, PROTECTED, PACKAGE, PRIVATE, NONE
    }

    annotation class Getter(val value: AccessLevel = AccessLevel.PUBLIC)
    annotation class Setter(val value: AccessLevel = AccessLevel.PUBLIC)
    annotation class With(val value: AccessLevel = AccessLevel.PUBLIC)
    annotation class Data(val staticConstructor: String = "")
    annotation class Value(val staticConstructor: String = "")
    annotation class NonNull
    annotation class NoArgsConstructor(
        val access: AccessLevel = AccessLevel.PUBLIC,
        val force: Boolean = false,
        val staticName: String = ""
    )
    annotation class AllArgsConstructor(
        val access: AccessLevel = AccessLevel.PUBLIC,
        val staticName: String = ""
    )
    annotation class RequiredArgsConstructor(
        val access: AccessLevel = AccessLevel.PUBLIC,
        val staticName: String = ""
    )
    annotation class ToString(
        val includeFieldNames: Boolean = true,
        val onlyExplicitlyIncluded: Boolean = false
    ) {
        annotation class Include
        annotation class Exclude
    }
    annotation class EqualsAndHashCode(
        val onlyExplicitlyIncluded: Boolean = false
    ) {
        annotation class Include
        annotation class Exclude
    }
    annotation class Builder(
        val builderClassName: String = "",
        val builderMethodName: String = "builder",
        val buildMethodName: String = "build",
        val setterPrefix: String = ""
    )
    """

    private let accessorsStub = """
    package lombok.experimental

    annotation class Accessors(
        val fluent: Boolean = false,
        val chain: Boolean = false,
        val prefix: Array<String> = []
    )
    """

    private let slf4jStub = """
    package lombok.extern.slf4j

    annotation class Slf4j
    """

    @Test
    func lombokDataSynthesizesGettersSettersToStringEqualsHashCodeAndCtor() throws {
        let userSource = """
        package com.example

        import lombok.Data

        @Data
        class Person {
            val name: String = ""
            var age: Int = 0
            val active: Boolean = true
        }

        fun use(p: Person): String {
            p.setAge(30)
            val a: Int = p.getAge()
            val b: Boolean = p.isActive()
            val n: String = p.getName()
            return p.toString() + ":" + n + ":" + a + ":" + b
        }
        """

        try withTemporaryFiles(contents: [lombokStubs, userSource]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected Sema errors: \(errors.map(\.message))")

            let interner = ctx.interner
            let symbols = try #require(ctx.sema?.symbols)
            let personSym = try #require(symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("Person"),
            ]))

            let methods = symbols.declaredChildren(of: personSym)
                .compactMap { symbols.symbol($0) }
                .filter { $0.kind == .function }
                .map { interner.resolve($0.name) }

            #expect(methods.contains("getName"))
            #expect(methods.contains("getAge"))
            #expect(methods.contains("setAge"))
            #expect(methods.contains("isActive"))
            #expect(!methods.contains("setName"))
            #expect(methods.contains("toString"))
            #expect(methods.contains("equals"))
            #expect(methods.contains("hashCode"))
        }
    }

    @Test
    func lombokBuilderAndStaticConstructorAndSlf4jResolveInSema() throws {
        let userSource = """
        package com.example

        import lombok.Builder
        import lombok.AllArgsConstructor
        import lombok.Getter
        import lombok.extern.slf4j.Slf4j

        @Builder
        @AllArgsConstructor(staticName = "of")
        @Getter
        @Slf4j
        class Item {
            var title: String = ""
            var count: Int = 0
        }

        fun useBuilder(): Item {
            val a = Item.of("book", 3)
            val b = Item.builder().title("pen").count(2).build()
            val titleA: String = a.getTitle()
            return b
        }
        """

        try withTemporaryFiles(contents: [lombokStubs, slf4jStub, userSource]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected Sema errors: \(errors.map(\.message))")

            let symbols = try #require(ctx.sema?.symbols)
            let interner = ctx.interner
            let itemSym = try #require(symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("Item"),
            ]))
            let info = try #require(ctx.sema?.lombokClasses[itemSym])
            #expect(info.builderInfo != nil)
            #expect(info.logPropertySymbol != nil)
            #expect(!info.constructorSymbols.isEmpty)
        }
    }

    @Test
    func lombokAccessorsAndConfigRespected() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configPath = tempDir.appendingPathComponent("lombok.config").path
        let configText = """
        lombok.getter.noIsPrefix = true
        lombok.accessors.prefix += m_
        """
        try configText.write(toFile: configPath, atomically: true, encoding: .utf8)

        let userSource = """
        package com.example

        import lombok.Getter
        import lombok.Setter
        import lombok.With
        import lombok.experimental.Accessors

        @Getter
        @Setter
        @With
        @Accessors(chain = true)
        class Flags {
            var m_enabled: Boolean = false
            var count: Int = 1
        }

        fun testFlags(f: Flags): Flags {
            val e: Boolean = f.getEnabled()
            return f.setEnabled(true).setCount(5).withCount(7)
        }
        """

        try withTemporaryFiles(contents: [lombokStubs, accessorsStub, userSource]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: ["plugin:org.jetbrains.kotlin.lombok:config=\(configPath)"]
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected Sema errors: \(errors.map(\.message))")

            let symbols = try #require(ctx.sema?.symbols)
            let interner = ctx.interner
            let flagsSym = try #require(symbols.lookup(fqName: [
                interner.intern("com"), interner.intern("example"), interner.intern("Flags"),
            ]))
            let methods = symbols.declaredChildren(of: flagsSym)
                .compactMap { symbols.symbol($0) }
                .filter { $0.kind == .function }
                .map { interner.resolve($0.name) }

            #expect(methods.contains("getEnabled"))
            #expect(!methods.contains("isEnabled"))
            #expect(methods.contains("setEnabled"))
            #expect(methods.contains("withCount"))
        }
    }

    @Test
    func dynamicLombokJarInspectRecognizesPluginID() throws {
        let jarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/lombok-compiler-plugin.jar"
        guard FileManager.default.fileExists(atPath: jarPath),
              JvmPluginHostClient.shared.findJavaExecutable() != nil
        else { return }

        let descriptor = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: jarPath)
        #expect(descriptor.pluginId == "org.jetbrains.kotlin.lombok")
        #expect(descriptor.options.contains { $0.name == "config" })
    }
}
#endif
