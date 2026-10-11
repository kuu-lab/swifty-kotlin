@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

private struct AtomicfuNativeExpectation: Decodable {
    let api_identity: String
    let api_symbol: String
    let kind: String
    let visibility: String
    let signature: String
    let parameter_types: [String]
    let receiver_type: String?
    let return_type: String?
    let is_inline: Bool
    let parameter_has_defaults: [Bool]
    let type_parameter_bounds: [String]
    let annotations: [Annotation]
    struct Annotation: Decodable { let name: String; let arguments: [String] }
}

@Suite(.serialized)
struct AtomicfuBundledSourceRegistrationTests {
    private let positive = """
    @file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class, kotlin.concurrent.atomics.ExperimentalAtomicApi::class)
    @file:Suppress("DEPRECATION")
    import kotlinx.atomicfu.*
    import kotlinx.atomicfu.atomic as makeAtomic
    import kotlinx.atomicfu.AtomicInt as FuInt
    import kotlin.concurrent.AtomicInt as StandardInt
    import kotlin.concurrent.atomics.AtomicInt as CanonicalInt
    import kotlinx.atomicfu.locks.*
    fun registrations() {
        val int: FuInt = makeAtomic(1)
        val long: AtomicLong = atomic(1L)
        val bool: AtomicBoolean = atomic(true)
        val ref: AtomicRef<String?> = atomic<String?>(null)
        val qualified: kotlinx.atomicfu.AtomicInt = kotlinx.atomicfu.atomic(2)
        val standard: StandardInt = StandardInt(3)
        val canonical: CanonicalInt = CanonicalInt(4)
        val array = AtomicIntArray(1)
        val refs = atomicArrayOfNulls<String>(1)
        val lock: ReentrantLock = reentrantLock()
        synchronized(lock) { int.value = qualified.value }
        lock.withLock { int.incrementAndGet() }
        SynchronousMutex().withLock { long.incrementAndGet() }
        Trace().invoke { "event" }
        val handle: ParkingHandle = ParkingSupport.currentThreadHandle()
        ParkingSupport.unpark(handle)
        ref.value = refs[0].value
        array[0].value = int.value
    }
    """

    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("Input.kt")
        try source.write(to: path, atomically: true, encoding: .utf8)
        // Keep tiny Core inputs and configuration on every path, including
        // throwing #require and nonthrowing #expect failures in the inventory.
        let stdlib = library ? try testStdlibArtifactPath() : nil
        let ctx = makeCompilationContext(inputs: [path.path],
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false)
        let provenance: [String: Any] = ["input": path.path,
            "stdlib": stdlib ?? "SOURCE", "include_stdlib": ctx.options.includeStdlib,
            "allow_default_stdlib": ctx.options.allowDefaultStdlibLibrary]
        try JSONSerialization.data(withJSONObject: provenance, options: [.sortedKeys, .prettyPrinted])
            .write(to: directory.appendingPathComponent("input.provenance.json"))
        try #require(ctx.options.stdlibLibraryPath == stdlib, "Retained at \(directory.path)")
        try #require(ctx.options.includeStdlib == !library)
        try #require(!ctx.options.allowDefaultStdlibLibrary)
        if let stdlib {
            let manifest = try Data(contentsOf: URL(fileURLWithPath: stdlib).appendingPathComponent("manifest.json"))
            try manifest.write(to: directory.appendingPathComponent("stdlib-manifest.before.json"))
            let fields = try #require(try JSONSerialization.jsonObject(with: manifest) as? [String: Any])
            try #require(fields["libraryKind"] as? String == "stdlib")
        }
        return ctx
    }

    private func expectations() throws -> [AtomicfuNativeExpectation] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Atomicfu/native-api-150.json")
        return try JSONDecoder().decode([AtomicfuNativeExpectation].self, from: Data(contentsOf: file))
    }

    private func qualifiedName(_ id: SymbolID, _ sema: SemaModule, _ ctx: CompilationContext) -> String {
        sema.symbols.symbol(id)?.fqName.map(ctx.interner.resolve).joined(separator: ".") ?? "<missing>"
    }

    private func canonicalType(_ id: TypeID, parameters: [SymbolID], sema: SemaModule, ctx: CompilationContext) -> String {
        func suffix(_ n: Nullability) -> String { n == .nonNull ? "" : "?" }
        func type(_ id: TypeID) -> String { canonicalType(id, parameters: parameters, sema: sema, ctx: ctx) }
        switch sema.types.kind(of: id) {
        case .unit: return "kotlin.Unit"
        case .nullableUnit: return "kotlin.Unit?"
        case let .nothing(n): return "kotlin.Nothing" + suffix(n)
        case let .any(n): return "kotlin.Any" + suffix(n)
        case let .stringStruct(n): return "kotlin.String" + suffix(n)
        case let .primitive(p, n): return "kotlin." + p.kotlinName + suffix(n)
        case let .typeParam(t):
            return "#" + String(parameters.firstIndex(of: t.symbol) ?? -1) + suffix(t.nullability)
        case let .classType(t):
            let args = t.args.map { arg -> String in
                switch arg {
                case let .invariant(value): return type(value)
                case let .out(value): return "out" + type(value)
                case let .in(value): return "in" + type(value)
                case .star: return "*"
                }
            }
            return qualifiedName(t.classSymbol, sema, ctx) + (args.isEmpty ? "" : "<" + args.joined(separator: ",") + ">") + suffix(t.nullability)
        case let .functionType(t):
            return "kotlin.Function" + String(t.params.count) + "<" + (t.params + [t.returnType]).map(type).joined(separator: ",") + ">" + suffix(t.nullability)
        case let .kClassType(t): return "kotlin.reflect.KClass<" + type(t.argument) + ">" + suffix(t.nullability)
        case .error, .intersection: return "<unsupported-type>"
        }
    }

    private func candidates(_ row: AtomicfuNativeExpectation, sema: SemaModule, ctx: CompilationContext) -> [SymbolID] {
        var fq = row.api_symbol.replacingOccurrences(of: "/", with: ".")
        if row.api_symbol.contains(".<get-") || row.api_symbol.contains(".<set-") {
            let propertyName = String(fq.prefix(upTo: fq.range(of: ".<")!.lowerBound))
            let properties = sema.symbols.lookupAll(fqName: propertyName.split(separator: ".").map { ctx.interner.intern(String($0)) })
            return properties.compactMap { id in
                row.api_symbol.contains(".<get-")
                    ? sema.symbols.extensionPropertyGetterAccessor(for: id)
                    : sema.symbols.extensionPropertySetterAccessor(for: id)
            }
        }
        if row.kind == "constructor" {
            let owner = String(fq.dropLast(".<init>".count))
            // Constructors have compiler-specific FQ names. Match the actual
            // owner and exact parameter signature instead of guessing spelling.
            return sema.symbols.allSymbols().filter { symbol in
                symbol.kind == .constructor && sema.symbols.parentSymbol(for: symbol.id).map {
                    qualifiedName($0, sema, ctx) == owner
                } == true
            }.map(\.id)
        }
        fq = fq.replacingOccurrences(of: "ReentrantLock", with: "SynchronizedObject")
        return sema.symbols.lookupAll(fqName: fq.split(separator: ".").map { ctx.interner.intern(String($0)) })
    }

    private func callableMatches(_ row: AtomicfuNativeExpectation, id: SymbolID, sema: SemaModule, ctx: CompilationContext) -> Bool {
        guard let signature = sema.symbols.functionSignature(for: id) else {
            return !["function", "constructor"].contains(row.kind)
        }
        let types = signature.parameterTypes.map { canonicalType($0, parameters: signature.typeParameterSymbols, sema: sema, ctx: ctx) }
        guard types == row.parameter_types else { return false }
        if row.kind == "constructor" { return true }
        let result = canonicalType(signature.returnType, parameters: signature.typeParameterSymbols, sema: sema, ctx: ctx)
        guard result == row.return_type else { return false }
        // Member dispatch receivers do not appear as KLIB extension receivers.
        if let receiver = row.receiver_type {
            return signature.receiverType.map { canonicalType($0, parameters: signature.typeParameterSymbols, sema: sema, ctx: ctx) } == receiver
        }
        return true
    }

    @Test(arguments: [false, true])
    func all150PinnedNativeIdentitiesResolveToActualBundledSymbols(library: Bool) throws {
        let ctx = try context(positive, library: library)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let expected = try expectations()
        #expect(expected.count == 150)
        #expect(expected.filter { $0.visibility == "public" }.count == 142)
        #expect(expected.filter { $0.visibility == "internal" }.count == 8)
        var matched: Set<SymbolID> = []
        var actualRows: [[String: Any]] = []
        for row in expected {
            let matching = candidates(row, sema: sema, ctx: ctx).filter {
                callableMatches(row, id: $0, sema: sema, ctx: ctx)
            }
            #expect(matching.count == 1, "\(row.api_identity): expected one actual declaration, got \(matching)")
            let id = try #require(matching.first)
            #expect(matched.insert(id).inserted, "duplicate binding for \(row.api_identity)")
            let symbol = try #require(sema.symbols.symbol(id))
            #expect(String(describing: symbol.visibility) == row.visibility, "\(row.api_identity)")
            let kind: SymbolKind = switch row.kind {
            case "class": .class
            case "object": .object
            case "annotation_class": .annotationClass
            case "constructor": .constructor
            case "property": .property
            default: .function
            }
            #expect(symbol.kind == kind, "\(row.api_identity)")
            #expect(symbol.flags.contains(.importedLibrary) == library)
            if !library {
                let file = sema.symbols.sourceFileID(for: id) ?? symbol.declSite?.start.file
                    ?? sema.symbols.parentSymbol(for: id).flatMap { sema.symbols.sourceFileID(for: $0) }
                let source = try #require(file, "source-backed owner/accessor required: \(row.api_identity)")
                #expect(ctx.sourceManager.path(of: source).contains("__bundled_kotlinx/atomicfu/"))
            }
            let annotations = sema.symbols.annotations(for: id)
            if row.kind == "function" {
                #expect(symbol.flags.contains(.inlineFunction) == row.is_inline, "inline flag: \(row.api_identity)")
            }
            if let signature = sema.symbols.functionSignature(for: id) {
                #expect(signature.parameterTypes.indices.map {
                    $0 < signature.valueParameterHasDefaultValues.count && signature.valueParameterHasDefaultValues[$0]
                } == row.parameter_has_defaults,
                        "default parameters: \(row.api_identity)")
            }
            for required in row.annotations {
                // SOURCE annotations are not exported. The source lane checks
                // them; the imported lane checks retained semantic annotations.
                if library && ["Suppress", "OptIn"].contains(required.name) { continue }
                #expect(annotations.contains { annotation in
                    annotation.annotationFQName.split(separator: ".").last == Substring(required.name)
                        && required.arguments.allSatisfy { arg in annotation.arguments.contains(arg) }
                }, "missing semantic annotation \(required) for \(row.api_identity)")
            }
            if row.kind == "property" {
                #expect(symbol.flags.contains(.mutable) == row.signature.contains(" var "), "\(row.api_identity)")
            }
            let function = sema.symbols.functionSignature(for: id)
            let declaredParameters: [SymbolID]
            if let function {
                declaredParameters = Array(function.typeParameterSymbols.dropFirst(function.classTypeParameterCount))
            } else if [.class, .annotationClass, .object].contains(symbol.kind) {
                declaredParameters = sema.symbols.allSymbols().filter {
                    $0.kind == .typeParameter && sema.symbols.parentSymbol(for: $0.id) == id
                }.map(\.id).sorted { $0.rawValue < $1.rawValue }
            } else { declaredParameters = [] }
            let bounds = declaredParameters.map { parameter in
                canonicalType(sema.symbols.typeParameterUpperBound(for: parameter) ?? sema.types.nullableAnyType,
                    parameters: declaredParameters, sema: sema, ctx: ctx)
            }
            #expect(bounds == row.type_parameter_bounds, "type parameter bounds: \(row.api_identity)")
            let actualReturn: Any = function.map {
                canonicalType($0.returnType, parameters: $0.typeParameterSymbols, sema: sema, ctx: ctx)
            } as Any? ?? NSNull()
            let actualReceiver: Any
            if row.receiver_type != nil, let function, let receiver = function.receiverType {
                actualReceiver = canonicalType(receiver, parameters: function.typeParameterSymbols, sema: sema, ctx: ctx)
            } else { actualReceiver = NSNull() }
            actualRows.append([
                "api_identity": row.api_identity,
                "symbol_id": id.rawValue,
                "actual_fq_name": qualifiedName(id, sema, ctx),
                "kind": row.kind,
                "actual_kind": String(describing: symbol.kind),
                "source_backed": sema.symbols.isSourceBackedSymbol(id),
                "visibility": String(describing: symbol.visibility),
                "parameter_types": function?.parameterTypes.map {
                    canonicalType($0, parameters: function!.typeParameterSymbols, sema: sema, ctx: ctx)
                } ?? [],
                "return_type": actualReturn,
                "receiver_type": actualReceiver,
                "is_inline": symbol.flags.contains(.inlineFunction),
                "parameter_has_defaults": function?.parameterTypes.indices.map {
                    $0 < function!.valueParameterHasDefaultValues.count && function!.valueParameterHasDefaultValues[$0]
                } ?? [],
                "type_parameter_bounds": bounds,
                "mutable": symbol.flags.contains(.mutable),
                "imported_library": symbol.flags.contains(.importedLibrary),
                "annotations": annotations.map { ["name": $0.annotationFQName, "arguments": $0.arguments] },
            ])
        }
        #expect(matched.count == 150)
        let all = sema.symbols.allSymbols()
        let initializerIDs = Set(all.filter { owner in
            [.class, .object, .annotationClass].contains(owner.kind)
                && qualifiedName(owner.id, sema, ctx).hasPrefix("kotlinx.atomicfu.")
        }.flatMap { owner in
            [sema.symbols.objectInitializerSymbol(for: owner.id),
             sema.symbols.objectLazyInitializerSymbol(for: owner.id),
             sema.symbols.companionObjectInitializerSymbol(for: owner.id)].compactMap { $0 }
        })
        let extras = all.filter { symbol in
            let name = qualifiedName(symbol.id, sema, ctx)
            guard name.hasPrefix("kotlinx.atomicfu."),
                  [.class, .object, .annotationClass, .constructor, .property, .function].contains(symbol.kind),
                  !matched.contains(symbol.id),
                  !symbol.flags.contains(.extensionMemberAlias)
            else { return false }
            // Generated imported object initializers are verified by their
            // owner registration and exact zero-argument Unit shape.
            if initializerIDs.contains(symbol.id), symbol.flags.contains(.synthetic),
               let signature = sema.symbols.functionSignature(for: symbol.id),
               signature.parameterTypes.isEmpty, signature.returnType == sema.types.unitType { return false }
            return VisibilityChecker(symbols: sema.symbols, sourceManager: ctx.sourceManager).isPublicAPI(symbol)
        }.map { qualifiedName($0.id, sema, ctx) }
        #expect(extras.isEmpty, "unexpected atomicfu public/PublishedApi API: \(extras)")
        if let destination = ProcessInfo.processInfo.environment["ATOMICFU_API_SNAPSHOT_DIR"] {
            let directory = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let snapshot: [String: Any] = ["schema_version": 1,
                "status": "CAPTURED_REQUIRES_SWIFT_RESULT_AND_PINNED_CHECKER",
                "lane": library ? "library" : "source", "expected_count": 150,
                "rows": actualRows, "extra_public_or_published_api_symbols": extras]
            try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted])
                .write(to: directory.appendingPathComponent(library ? "library.json" : "source.json"))
        }
        for name in ["AtomicInt", "AtomicLong"] {
            let fu = try #require(sema.symbols.lookup(fqName: ["kotlinx", "atomicfu", name].map(ctx.interner.intern)))
            let standard = try #require(sema.symbols.lookup(fqName: ["kotlin", "concurrent", name].map(ctx.interner.intern)))
            let canonical = try #require(sema.symbols.lookup(fqName: ["kotlin", "concurrent", "atomics", name].map(ctx.interner.intern)))
            #expect(fu != standard && fu != canonical)
        }
    }

    @Test(arguments: [false, true])
    func standardAtomicOperationsAndInternalKernelsDoNotLeak(library: Bool) throws {
        for source in [
            "import kotlinx.atomicfu.*\nfun bad() = atomic(1).load()",
            "import kotlinx.atomicfu.*\nfun bad() = atomic(1).store(2)",
            "import kotlinx.atomicfu.*\nfun bad() = atomic(1).compareAndExchange(1, 2)",
            "import kotlinx.atomicfu.*\nfun bad() = atomic(1).a",
            "fun bad() = kotlinx.atomicfu.AtomicInt(kotlin.concurrent.AtomicInt(0))",
            "import kotlinx.atomicfu.locks.*\nfun bad() = newAtomicfuLockKernel(0)",
            "fun bad() = kotlinx.atomicfu.locks.ParkingHandle()",
        ] {
            let ctx = try context(source, library: library)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "private/internal API leaked: \(source)")
        }
    }

    private let blockingCall = "fun caller() { kotlinx.atomicfu.locks.ParkingSupport.currentThreadHandle() }"
    private let blockingMarker = "kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi"
    private let blockingMessage = "This API is experimental. It is low-level and might change in the future."

    private func optInReceipt(_ ctx: CompilationContext, confirmed: Bool) throws {
        let input = try #require(ctx.options.inputs.first)
        let diagnostics = ctx.diagnostics.diagnostics.map { diagnostic in
            ["code": diagnostic.code, "severity": String(describing: diagnostic.severity),
             "message": diagnostic.message,
             "path": diagnostic.primaryRange.map { ctx.sourceManager.path(of: $0.start.file) } ?? "<none>"]
        }
        let fields: [String: Any] = ["status": confirmed ? "EXPECTED_CONTROL_CONFIRMED" : "FAIL_OR_INTERRUPTED",
            "input": input, "stdlib": ctx.options.stdlibLibraryPath ?? "SOURCE", "diagnostics": diagnostics]
        try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .prettyPrinted])
            .write(to: URL(fileURLWithPath: input).deletingLastPathComponent().appendingPathComponent("optin.diagnostics.json"))
    }

    private func realBlockingCall(_ ctx: CompilationContext, library: Bool) throws -> SymbolID {
        let sema = try #require(ctx.sema)
        let marker = try #require(sema.symbols.lookup(fqName: blockingMarker.split(separator: ".").map {
            ctx.interner.intern(String($0))
        }))
        let markerInfo = try #require(sema.symbols.symbol(marker))
        try #require(markerInfo.kind == .annotationClass && markerInfo.visibility == .public)
        try #require(markerInfo.flags.contains(.importedLibrary) == library)
        let optIn = try #require(sema.symbols.annotations(for: marker).first {
            $0.annotationFQName == "kotlin.RequiresOptIn"
        })
        try #require(optIn.arguments.contains("level=RequiresOptIn.Level.ERROR"))
        try #require(optIn.arguments.contains("message=\"" + blockingMessage + "\""))
        let ast = try #require(ctx.ast)
        let input = try #require(ctx.options.inputs.first)
        let calls = sema.bindings.callBindings.filter { expression, binding in
            guard let range = ast.arena.exprRange(expression),
                  ctx.sourceManager.path(of: range.start.file) == input
            else { return false }
            return qualifiedName(binding.chosenCallee, sema, ctx) == "kotlinx.atomicfu.locks.ParkingSupport.currentThreadHandle"
        }
        try #require(calls.count == 1, "Actual user call must bind exactly once: \(input)")
        let callee = try #require(calls.first?.value.chosenCallee)
        let symbol = try #require(sema.symbols.symbol(callee))
        try #require(symbol.kind == .function && symbol.visibility == .public)
        try #require(symbol.flags.contains(.importedLibrary) == library)
        try #require(!symbol.flags.contains(.synthetic))
        if library {
            // Ordinary compiled Kotlin functions have an imported link name.
            // Reject only these eight private mechanism bridges, not kk_ names.
            let link = try #require(sema.symbols.externalLinkName(for: callee))
            try #require(!link.isEmpty)
            let privateBridges: Set<String> = [
                "__kk_atomicfu_current_parking_handle", "__kk_atomicfu_lock_lock",
                "__kk_atomicfu_lock_new", "__kk_atomicfu_lock_try_lock",
                "__kk_atomicfu_lock_unlock", "__kk_atomicfu_parker_new",
                "__kk_atomicfu_parker_unpark", "__kk_atomicfu_parker_wait",
            ]
            try #require(!privateBridges.contains(link))
        } else {
            try #require(sema.symbols.externalLinkName(for: callee) == nil)
        }
        let signature = try #require(sema.symbols.functionSignature(for: callee))
        try #require(signature.parameterTypes.isEmpty)
        try #require(canonicalType(signature.returnType, parameters: signature.typeParameterSymbols,
            sema: sema, ctx: ctx) == "kotlinx.atomicfu.locks.ParkingHandle")
        if !library {
            try #require(sema.symbols.isSourceBackedSymbol(callee))
            let file = try #require(sema.symbols.sourceFileID(for: callee) ?? symbol.declSite?.start.file)
            try #require(ctx.sourceManager.path(of: file).contains("__bundled_kotlinx/atomicfu/"))
        }
        return callee
    }

    @Test(arguments: [false, true])
    func realThreadBlockingApiRejectsUnoptedSourceAndProductionStdlibConsumers(library: Bool) throws {
        let ctx = try context(blockingCall, library: library)
        var confirmed = false
        defer { try? optInReceipt(ctx, confirmed: confirmed) }
        try runSema(ctx)
        try optInReceipt(ctx, confirmed: false) // Capture real diagnostics before assertions.
        _ = try realBlockingCall(ctx, library: library)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(!errors.isEmpty, "RequiresOptIn.ERROR must reject this real API call")
        try #require(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" &&
            $0.message.contains(blockingMarker) && $0.message.contains(blockingMessage) })
        let input = try #require(ctx.options.inputs.first)
        try #require(errors.allSatisfy { diagnostic in
            diagnostic.primaryRange.map { ctx.sourceManager.path(of: $0.start.file) == input } == true
        }, "Unrelated Stdlib errors cannot satisfy the negative control")
        try #require(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning })
        confirmed = true
    }

    @Test(arguments: [false, true])
    func optInAllowsTheSameActualThreadBlockingCallThroughSourceAndProductionStdlib(library: Bool) throws {
        let ctx = try context("@file:OptIn(\(blockingMarker)::class)\n" + blockingCall, library: library)
        var confirmed = false
        defer { try? optInReceipt(ctx, confirmed: confirmed) }
        try runSema(ctx)
        try optInReceipt(ctx, confirmed: false)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        try #require(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" })
        _ = try realBlockingCall(ctx, library: library)
        confirmed = true
    }
}
