#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct InferredTopLevelPropertyForwardReferenceTests {
    // KUU-3912 (ktor-http IpParser.kt): a top-level `val` whose type is only
    // inferred used to keep its header-registered `Any?` placeholder while a
    // reader in an earlier-processed file — or earlier in the same file —
    // resolved a member on it. `kotlinc` accepts all of these shapes; the
    // safe precheck now publishes the inferred type before the reader's pass
    // runs. An explicit type annotation always avoided the issue.
    private static let libGrammar = """
    package lib
    internal class Grammar {
        fun member(input: String): Boolean = true
    }
    internal fun Grammar.ext(input: String): Boolean = true
    internal infix fun Grammar.or(other: Grammar): Grammar = this
    internal val getterInferred get() = Grammar()
    internal val initInferred = Grammar()
    internal val infixInferred = Grammar() or Grammar()
    """

    private static let useGrammar = """
    package use
    import lib.*
    fun check(host: String): Boolean =
        getterInferred.member(host) && getterInferred.ext(host)
            && initInferred.member(host) && initInferred.ext(host)
            && infixInferred.member(host)
    """

    @Test(arguments: [true, false])
    func getterAndInfixInferredPropertiesResolveAcrossFileOrder(consumerFirst: Bool) throws {
        let sources = consumerFirst
            ? [Self.useGrammar, Self.libGrammar]
            : [Self.libGrammar, Self.useGrammar]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected the earlier-file reader to see the inferred Grammar type, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func sameFileUseBeforeDeclarationResolves() throws {
        let source = """
        package same
        internal class Grammar
        internal infix fun Grammar.or(other: Grammar): Grammar = this
        internal fun Grammar.match(input: String): Boolean = true
        fun hostIsIp(host: String): Boolean = SPECIAL.match(host)
        internal val SPECIAL = Grammar() or Grammar()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected the same-file forward reference to see Grammar, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test(arguments: [true, false])
    func argumentBearingFactoryInitializerResolvesAcrossFileOrder(consumerFirst: Bool) throws {
        // `listOf("")`-style initializers bind the factory's bare type
        // parameter from the argument, so the inferred `List<String>` stays
        // visible to earlier-processed readers.
        let lib = """
        package lib
        internal val ROOT = listOf("")
        internal val ids = setOf(1, 2)
        """
        let use = """
        package use
        import lib.*
        fun size(): Int = ROOT.size + ids.size
        fun joined(): String = ROOT.joinToString()
        """
        let sources = consumerFirst ? [use, lib] : [lib, use]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected listOf/setOf initializers to publish their inferred types, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test(arguments: [true, false])
    func genericConstructorInitializerBindsTypeArgumentsAcrossFileOrder(consumerFirst: Bool) throws {
        // `Pair("k", 1)` pins both class type parameters from the constructor
        // arguments, so `p.first` is String and `p.second` is Int even for an
        // earlier-processed reader.
        let lib = """
        package lib
        internal val p = Pair("k", 1)
        """
        let use = """
        package use
        import lib.*
        fun first(): String = p.first
        fun second(): Int = p.second
        """
        let sources = consumerFirst ? [use, lib] : [lib, use]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Pair(\"k\", 1) to publish Pair<String, Int>, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let pair = try #require(sema.symbols.lookup(
            fqName: ["kotlin", "Pair"].map(ctx.interner.intern)
        ))
        let property = try #require(sema.symbols.lookup(
            fqName: ["lib", "p"].map(ctx.interner.intern)
        ))
        guard case let .classType(classType) = sema.types.kind(
            of: sema.symbols.propertyType(for: property) ?? sema.types.errorType
        ) else {
            Issue.record("Expected lib.p to keep a nominal Pair type")
            return
        }
        #expect(classType.classSymbol == pair)
        #expect(classType.args.count == 2)
        guard case let .invariant(firstArg) = classType.args[0],
              case let .invariant(secondArg) = classType.args[1]
        else {
            Issue.record("Expected invariant Pair type arguments")
            return
        }
        #expect(firstArg == sema.types.stringType)
        #expect(secondArg == sema.types.intType)
    }

    // KUU-4278 (kotlinx-datetime `LocalDateTimeFormat.kt:80` and sibling
    // `DateTimeComponents.kt:108`): `internal val ISO_DATE/ISO_TIME by lazy {
    // XFormat.build { ... } }` kept the header `Any?` placeholder for readers
    // checked before the declaring file. The safe precheck cannot prove a
    // call whose arguments include a lambda on a companion-scope receiver, so
    // the property stayed pending and `date(ISO_DATE)`/`time(ISO_TIME)` failed
    // constraint solving with KSWIFTK-SEMA-0473 even though `kotlinc` accepts
    // the module. On-demand inference now resolves the pending property when
    // the reader binds it.
    @Test(arguments: [true, false])
    func delegatedBuilderPropertiesResolveAcrossFileOrder(consumerFirst: Bool) throws {
        let lib = """
        package lib
        interface DateTimeFormat<T>
        class LocalDate
        class LocalTime

        interface WithDate {
            fun year()
            fun monthNumber()
            fun day()
        }
        interface WithTime {
            fun hour()
            fun minute()
        }

        interface DateTimeFormatBuilder {
            fun date(format: DateTimeFormat<LocalDate>)
            fun time(format: DateTimeFormat<LocalTime>)
        }

        class FormatBuilder : DateTimeFormatBuilder, WithDate, WithTime {
            override fun date(format: DateTimeFormat<LocalDate>) {}
            override fun time(format: DateTimeFormat<LocalTime>) {}
            override fun year() {}
            override fun monthNumber() {}
            override fun day() {}
            override fun hour() {}
            override fun minute() {}
        }

        class LocalDateFormat private constructor() : DateTimeFormat<LocalDate> {
            companion object {
                fun build(block: WithDate.() -> Unit): DateTimeFormat<LocalDate> {
                    FormatBuilder().block()
                    return LocalDateFormat()
                }
            }
        }

        class LocalTimeFormat private constructor() : DateTimeFormat<LocalTime> {
            companion object {
                fun build(block: WithTime.() -> Unit): LocalTimeFormat {
                    FormatBuilder().block()
                    return LocalTimeFormat()
                }
            }
        }

        internal val ISO_DATE by lazy {
            LocalDateFormat.build {
                year()
                monthNumber()
                day()
            }
        }
        internal val ISO_TIME by lazy {
            LocalTimeFormat.build {
                hour()
                minute()
            }
        }

        fun runFormat(block: DateTimeFormatBuilder.() -> Unit) {
            FormatBuilder().block()
        }
        """
        let use = """
        package use
        import lib.*
        fun buildFormats() = runFormat {
            date(ISO_DATE)
            time(ISO_TIME)
        }
        """
        let sources = consumerFirst ? [use, lib] : [lib, use]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected earlier-file readers to see the delegated formats' inferred types, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func nonInfixCallStillRequiresTheModifier() throws {
        // The precheck must not launder invalid Kotlin: `a or b` without the
        // `infix` modifier stays a normal-pass failure, so the reader still
        // reports the unresolved member instead of seeing a fabricated type.
        let source = """
        package same
        internal class Grammar
        internal fun Grammar.or(other: Grammar): Grammar = this
        internal fun Grammar.match(input: String): Boolean = true
        fun hostIsIp(host: String): Boolean = SPECIAL.match(host)
        internal val SPECIAL = Grammar() or Grammar()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0307" })
    }

    @Test
    func unknownMemberOnForwardReferenceStillReportsUnresolved() throws {
        // Inferring the property type early must not make every member name
        // resolve: a genuinely missing member keeps its SEMA-0024 diagnostic.
        let source = """
        package same
        internal class Grammar
        internal infix fun Grammar.or(other: Grammar): Grammar = this
        fun hostIsIp(host: String): Boolean = SPECIAL.missing(host)
        internal val SPECIAL = Grammar() or Grammar()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }
}
#endif
