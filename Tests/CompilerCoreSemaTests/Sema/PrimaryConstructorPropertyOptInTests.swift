@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct PrimaryConstructorPropertyOptInTests {
    private func check(_ source: String, frontendFlags: [String] = []) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource(source, frontendFlags: frontendFlags, allowDefaultStdlibLibrary: true)
        do {
            try runSema(context)
        } catch {
            // Negative cases assert the collected diagnostics below.
        }
        return context
    }

    private func markerSource(level: String = "ERROR") -> String {
        """
        @RequiresOptIn(level = RequiresOptIn.Level.\(level))
        annotation class Gate
        @Gate
        class Experimental
        """
    }

    private func optInDiagnostics(_ context: CompilationContext) -> [Diagnostic] {
        context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
    }

    @Test(arguments: ["val", "var"], ["OptIn", "param:OptIn", "property:OptIn"])
    func respectsParameterAndPropertySitesWithoutMovingAnnotations(kind: String, annotation: String) throws {
        let context = check(markerSource() + "\nclass Holder(@\(annotation)(Gate::class) \(kind) value: Experimental)")
        let isPropertyOnly = annotation == "property:OptIn"
        let expectedDiagnosticCount = isPropertyOnly ? 1 : 0
        let expectedOptInCount = isPropertyOnly ? 1 : 0

        #expect(context.diagnostics.hasError == isPropertyOnly, "\(context.diagnostics.diagnostics)")
        #expect(optInDiagnostics(context).count == expectedDiagnosticCount)
        let sema = try #require(context.sema)
        let property = try #require(sema.symbols.allSymbols().first {
            $0.fqName.map(context.interner.resolve) == ["Holder", "value"]
        })
        let optIns = sema.symbols.annotations(for: property.id).filter {
            $0.annotationFQName == "kotlin.OptIn"
        }
        #expect(optIns.count == expectedOptInCount)
        #expect(optIns.allSatisfy { $0.useSiteTarget == "property" })
    }

    @Test(arguments: ["WARNING", "ERROR"], [false, true])
    func siblingConsentIsLimitedToItsOwnHeader(level: String, optInFirst: Bool) throws {
        let consent = "@OptIn(Gate::class) "
        let context = check(markerSource(level: level) + """

        class Holder(\(optInFirst ? consent : "")val first: Experimental, \(optInFirst ? "" : consent)val second: Experimental)
        """)
        let diagnostics = optInDiagnostics(context)
        let expectedSeverity: DiagnosticSeverity = level == "ERROR" ? .error : .warning
        #expect(diagnostics.count == 1, "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == expectedSeverity })
        let sema = try #require(context.sema)
        let optedProperties = sema.bindings.primaryConstructorPropertyParameters.filter {
            !$0.value.parameter.annotations.isEmpty
                && sema.symbols.symbol($0.key)?.fqName.first.map(context.interner.resolve) == "Holder"
        }
        #expect(optedProperties.count == 1)
        let expectedOptedPropertyName = optInFirst ? "first" : "second"
        #expect(optedProperties.keys.allSatisfy {
            sema.symbols.symbol($0).map { context.interner.resolve($0.name) } == expectedOptedPropertyName
        })
    }

    @Test(arguments: ["", "param:"])
    func acceptsResolvedOptInImportAlias(site: String) {
        let context = check("import kotlin.OptIn as Consent\n" + markerSource() + "\nclass Holder(@\(site)Consent(Gate::class) val value: Experimental)")
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(optInDiagnostics(context).isEmpty)
    }

    @Test
    func unrelatedSameNamedAnnotationDoesNotGrantConsent() {
        let context = check("package example\nimport kotlin.reflect.KClass\n" + markerSource() + """

        annotation class OptIn(vararg val markerClass: KClass<*>)
        class Holder(@OptIn(Gate::class) val value: Experimental)
        """)
        #expect(context.diagnostics.hasError)
        #expect(optInDiagnostics(context).count == 1, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func correspondenceSkipsPlainParameters() {
        let context = check(markerSource() + """

        class Holder(plain: Int, @OptIn(Gate::class) val first: Experimental, other: String, @param:OptIn(Gate::class) var last: Experimental)
        """)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(optInDiagnostics(context).isEmpty)
    }

    @Test(arguments: [false, true])
    func localPrimaryPropertyChecksRetainTheSameConsentBoundary(optedIn: Bool) {
        let context = check(markerSource() + """

        fun host() {
            class Holder(\(optedIn ? "@OptIn(Gate::class) " : "")val value: Experimental)
        }
        """)
        let expectedHasError = !optedIn
        let expectedDiagnosticCount = optedIn ? 0 : 1
        #expect(context.diagnostics.hasError == expectedHasError, "\(context.diagnostics.diagnostics)")
        #expect(optInDiagnostics(context).count == expectedDiagnosticCount, "\(context.diagnostics.diagnostics)")
    }

    @Test
    func consentDoesNotLeakToOtherOwnersOrNestedProperties() {
        let context = check(markerSource() + """

        class Accepted(@OptIn(Gate::class) val value: Experimental) {
            val bodyProperty: Experimental? = null
            class Nested(val value: Experimental)
        }
        class Rejected(val value: Experimental)
        """)
        #expect(optInDiagnostics(context).count == 3, "\(context.diagnostics.diagnostics)")
        #expect(context.diagnostics.hasError)
    }

    @Test
    func parameterConsentDoesNotAuthorizeUnrelatedSignature() {
        let context = check(markerSource() + """

        class Holder(@OptIn(Gate::class) val value: Experimental)
        fun caller(holder: Holder): Experimental? = null
        """)
        let diagnostics = optInDiagnostics(context)
        #expect(!diagnostics.isEmpty, "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy {
            $0.primaryRange.map { context.sourceManager.lineColumn(of: $0.start).line == 6 } == true
        }, "\(diagnostics)")
    }

    @Test(arguments: ["WARNING", "ERROR"])
    func preservesUnoptedSeverityAndEnclosingConsent(level: String) {
        let unopted = check(markerSource(level: level) + "\nclass Holder(val value: Experimental)")
        let expectedHasError = level == "ERROR"
        #expect(optInDiagnostics(unopted).count == 1, "\(unopted.diagnostics.diagnostics)")
        #expect(unopted.diagnostics.hasError == expectedHasError)
        for declaration in [
            "@OptIn(Gate::class) class Holder(val value: Experimental)",
            "class Holder(@OptIn(Gate::class) value: Experimental)",
        ] {
            let context = check(markerSource(level: level) + "\n" + declaration)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            #expect(optInDiagnostics(context).isEmpty)
        }
        let file = check("@file:OptIn(Gate::class)\n" + markerSource(level: level) + "\nclass Holder(val value: Experimental)")
        #expect(optInDiagnostics(file).isEmpty, "\(file.diagnostics.diagnostics)")
        let global = check(markerSource(level: level) + "\nclass Holder(val value: Experimental)", frontendFlags: ["opt-in=Gate"])
        #expect(optInDiagnostics(global).isEmpty, "\(global.diagnostics.diagnostics)")
    }

    @Test(arguments: ["", "OptIn", "param:OptIn", "property:OptIn"])
    func unsignedVarargAnnotationPropertyRetainsRequiredWarnings(annotation: String) {
        let consent = annotation.isEmpty ? "" : "@\(annotation)(ExperimentalUnsignedTypes::class) "
        let context = check("annotation class Tags(\(consent)vararg val tags: ULong)")
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let diagnostics = optInDiagnostics(context)
        let expectedDiagnosticCount = (annotation.isEmpty || annotation == "property:OptIn") ? 1 : 0
        #expect(diagnostics.count == expectedDiagnosticCount, "\(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
    }
}
