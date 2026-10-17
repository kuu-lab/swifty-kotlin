#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct SegmentReadContextShapeTests {
    private let interfaceFQName = "kotlinx.io.unsafe.SegmentReadContext"
    private let methodFQName = "kotlinx.io.unsafe.SegmentReadContext.getUnchecked"

    private func repositoryRoot() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root
    }

    private func parsedSourceInterface() throws -> (ASTModule, CompilationContext, InterfaceDecl) {
        let path = repositoryRoot()
            .appendingPathComponent("Sources/CompilerCore/Stdlib/kotlinx/io/unsafe/UnsafeBufferOperations.kt")
            .path
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        try LoadSourcesPhase().run(context)
        try LexPhase().run(context)
        try ParsePhase().run(context)
        try BuildASTPhase().run(context)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")

        let ast = try #require(context.ast)
        let interfaces = ast.arena.declarations().compactMap { declaration -> InterfaceDecl? in
            guard case let .interfaceDecl(interface) = declaration,
                  context.interner.resolve(interface.name) == "SegmentReadContext"
            else { return nil }
            return interface
        }
        try #require(interfaces.count == 1, "Expected one production SegmentReadContext declaration")
        return (ast, context, try #require(interfaces.first))
    }

    private func namedTypePath(
        _ typeID: TypeRefID?,
        ast: ASTModule,
        context: CompilationContext
    ) throws -> [String] {
        let typeID = try #require(typeID)
        guard case let .named(path, arguments, nullable)? = ast.arena.typeRef(typeID) else {
            Issue.record("Expected a named non-null type")
            return []
        }
        #expect(arguments.isEmpty)
        #expect(!nullable)
        return path.map(context.interner.resolve)
    }

    private func stdlibLibraryURL() throws -> URL {
        if let explicitPath = ProcessInfo.processInfo.environment["KSWIFTK_SEGMENT_READ_CONTEXT_TEST_KLIB"],
           !explicitPath.isEmpty
        {
            return URL(fileURLWithPath: explicitPath, isDirectory: true)
        }
        TestStdlibCache.shared.prepare()
        return URL(fileURLWithPath: try #require(CompilerOptions.defaultStdlibLibraryPath), isDirectory: true)
    }

    private func ledgerRows() throws -> [String: [String: String]] {
        let path = repositoryRoot().appendingPathComponent("Scripts/io_api_inventory/api-inventory.tsv")
        let lines = try String(contentsOf: path, encoding: .utf8).components(separatedBy: .newlines)
        let headers = lines[0].components(separatedBy: "\t")
        let rowIDIndex = try #require(headers.firstIndex(of: "row_id"))
        var rows: [String: [String: String]] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let fields = line.components(separatedBy: "\t")
            guard fields.count == headers.count else { continue }
            let decodedFields = fields.map { field in
                guard field.hasPrefix("\""), field.hasSuffix("\"") else { return field }
                return String(field.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
            }
            rows[decodedFields[rowIDIndex]] = Dictionary(uniqueKeysWithValues: zip(headers, decodedFields))
        }
        return rows
    }

    private func platformMetadata(_ row: [String: String]) throws -> [String: Any] {
        let raw = try #require(row["platform_metadata"])
        let entries = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        return try #require(entries.first)
    }

    @Test
    func fixedLedgerRowsKeepTheTwoInterfaceViewsPaired() throws {
        let rows = try ledgerRows()
        let jvm = try #require(rows["jvm-b98e822f37597b93"])
        let klib = try #require(rows["klib-f6fe9eab2b16817b"])

        #expect(jvm["representation"] == "JVM public ABI dump")
        #expect(jvm["api_kind"] == "interface")
        #expect(jvm["owner_fqn"] == "kotlinx/io/unsafe/SegmentReadContext")
        #expect(jvm["signature"] == "public abstract interface class kotlinx/io/unsafe/SegmentReadContext {")
        #expect(jvm["annotations"] == "UnsafeIoApi")
        #expect(jvm["jvm_abi_refs"] == "klib-f6fe9eab2b16817b")

        let jvmMethod = try #require(rows["jvm-0caaa0484d9a8094"])
        #expect(jvmMethod["owner_fqn"] == "kotlinx/io/unsafe/SegmentReadContext")
        #expect(jvmMethod["name"] == "getUnchecked")
        #expect(jvmMethod["signature"] == "public abstract fun getUnchecked (Lkotlinx/io/Segment;I)B")
        #expect(jvmMethod["annotations"] == "none")
        let jvmMetadata = try platformMetadata(jvmMethod)
        #expect((jvmMetadata["defaults"] as? [String: Any])?.isEmpty == true)
        #expect(jvmMetadata["exceptionContract"] as? String == "not-declared-in-source")

        let klibMethod = try #require(rows["klib-8408acee5eedc7d9"])
        #expect(klibMethod["owner_fqn"] == "kotlinx.io.unsafe/SegmentReadContext")
        #expect(klibMethod["signature"] == "abstract fun getUnchecked(kotlinx.io/Segment, kotlin/Int): kotlin/Byte")
        #expect(klibMethod["annotations"] == "none")
        let klibMetadata = try platformMetadata(klibMethod)
        #expect((klibMetadata["defaults"] as? [String: Any])?.isEmpty == true)
        #expect(klibMetadata["exceptionContract"] as? String == "not-declared-in-source")

        #expect(klib["representation"] == "Kotlin source API / KLIB dump")
        #expect(klib["api_kind"] == "interface")
        #expect(klib["owner_fqn"] == "kotlinx.io.unsafe/SegmentReadContext")
        #expect(klib["signature"] == "abstract interface kotlinx.io.unsafe/SegmentReadContext {")
        #expect(klib["annotations"] == "UnsafeIoApi")
        #expect(klib["jvm_abi_refs"] == "jvm-b98e822f37597b93")
    }

    @Test
    func productionSourceHasTheExpectedInterfaceAndMemberShape() throws {
        let (ast, context, interface) = try parsedSourceInterface()
        let packages = ast.sortedFiles.map { file in
            file.packageFQName.map(context.interner.resolve)
        }
        #expect(packages.contains(["kotlinx", "io", "unsafe"]))
        #expect(context.interner.resolve(interface.name) == "SegmentReadContext")
        #expect(interface.modifiers.contains(.public))
        #expect(!interface.isFunInterface)
        #expect(interface.typeParams.isEmpty)
        #expect(interface.superTypes.isEmpty)
        #expect(interface.memberProperties.isEmpty)
        #expect(interface.nestedClasses.isEmpty && interface.nestedObjects.isEmpty)
        #expect(interface.annotations.map(\.name) == ["UnsafeIoApi"])
        #expect(interface.annotations.allSatisfy { $0.arguments.isEmpty && $0.useSiteTarget == nil })

        let methods = interface.memberFunctions.compactMap { ast.arena.decl($0) }.compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = declaration else { return nil }
            return function
        }
        try #require(methods.count == 1, "Expected only the direct getUnchecked member")
        let method = try #require(methods.first)
        #expect(context.interner.resolve(method.name) == "getUnchecked")
        #expect(method.modifiers.contains(.public))
        #expect(method.annotations.isEmpty)
        #expect(method.typeParams.isEmpty)
        #expect(method.receiverType == nil)
        #expect(method.contextReceivers.isEmpty)
        #expect(!method.isSuspend && !method.isInline && !method.isTailrec)
        #expect(method.body == .unit)
        #expect(method.valueParams.map { context.interner.resolve($0.name) } == ["segment", "offset"])
        #expect(method.valueParams.map(\.hasDefaultValue) == [false, false])
        #expect(method.valueParams.map(\.isVararg) == [false, false])
        #expect(try method.valueParams.map { try namedTypePath($0.type, ast: ast, context: context) } == [["Segment"], ["Int"]])
        #expect(try namedTypePath(method.returnType, ast: ast, context: context) == ["Byte"])
    }

    @Test
    func generatedKlibHasTheExpectedInterfaceAndMemberShape() throws {
        let artifact = try stdlibLibraryURL()
        let manifest = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: artifact.appendingPathComponent("manifest.json"))
        ) as? [String: Any])
        #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
        #expect(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
        #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())

        let records = MetadataDecoder().decode(try Data(contentsOf: artifact.appendingPathComponent("metadata.bin")))
        let interfaceRecords = records.filter { $0.fqName == interfaceFQName && $0.kind == .interface }
        try #require(interfaceRecords.count == 1)
        let interface = try #require(interfaceRecords.first)
        #expect(interface.visibility == .public)
        #expect(!interface.isFunInterface)
        #expect(interface.nominalTypeParameters == nil || interface.nominalTypeParameters?.isEmpty == true)
        #expect(interface.nominalSupertypeSignatures.isEmpty)
        let annotations = interface.annotations.filter { $0.annotationFQName == "kotlinx.io.UnsafeIoApi" }
        #expect(annotations.count == 1)
        #expect(annotations.allSatisfy { $0.arguments.isEmpty && $0.useSiteTarget == nil })

        let methods = records.filter { $0.fqName == methodFQName && $0.kind == .function }
        try #require(methods.count == 1)
        let method = try #require(methods.first)
        #expect(method.visibility == .public)
        #expect(method.modality == .abstract)
        #expect(method.receiverOwnerFQName == interfaceFQName)
        #expect(method.typeSignature == "F2<RLkotlinx.io.unsafe.SegmentReadContext;,Lkotlinx.io.Segment;,I,B>")
        #expect(method.valueParameterNames == ["segment", "offset"])
        #expect(method.valueParameterHasDefaultValues == [false, false])
        #expect(method.valueParameterIsVararg == [false, false])
        #expect(method.callableTypeParameterSignatures.isEmpty)
        #expect(!method.isSuspend)
    }
}
#endif
