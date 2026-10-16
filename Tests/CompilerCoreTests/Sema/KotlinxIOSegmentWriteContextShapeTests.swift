@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct KotlinxIOSegmentWriteContextShapeTests {
    private struct ShapeIndex: Decodable {
        struct APIPaths: Decodable {
            let jvm: String
            let klib: String
        }

        struct Interface: Decodable {
            struct Member: Decodable {
                let name: String
                let parameterNames: [String]
                let parameterTypeSignatures: [String]
                let returnTypeSignature: String
                let jvmDescriptor: String
                let klibSignature: String
            }

            let fqName: String
            let visibility: String
            let annotations: [String]
            let superFQNames: [String]
            let members: [Member]
        }

        let schemaVersion: Int
        let upstreamCommit: String
        let rowIDs: [String]
        let apiPaths: APIPaths
        let jvmInterfaceBlock: String
        let klibInterfaceBlock: String
        let interface: Interface
    }

    private func repositoryRoot() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root
    }

    private func index() throws -> ShapeIndex {
        let path = repositoryRoot().appendingPathComponent(
            "Scripts/kotlinx_io_upstream/unsafe/segment-write-context-shape.expected.json"
        )
        let result = try JSONDecoder().decode(ShapeIndex.self, from: Data(contentsOf: path))
        try #require(result.schemaVersion == 1)
        try #require(result.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        try #require(result.rowIDs == ["jvm-b7a5748618f52f9c", "klib-4ee0099543291bca"])
        try #require(result.interface.fqName == "kotlinx.io.unsafe.SegmentWriteContext")
        try #require(result.interface.members.count == 4)
        return result
    }

    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? CompilerOptions.defaultStdlibLibraryPath : nil
        if library { try #require(artifact != nil) }
        if let artifact {
            let directory = URL(fileURLWithPath: artifact, isDirectory: true)
            let manifest = try #require(JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            ) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let result = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = result.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(result.options.includeStdlib == !library && result.options.stdlibLibraryPath == artifact)
        return result
    }

    private func directConsumer() -> String {
        """
        @file:OptIn(kotlinx.io.UnsafeIoApi::class)
        import kotlinx.io.Segment
        import kotlinx.io.unsafe.SegmentWriteContext

        fun consume(context: SegmentWriteContext, segment: Segment) {
            context.setUnchecked(segment, 0, 1.toByte())
            context.setUnchecked(segment, 1, 2.toByte(), 3.toByte())
            context.setUnchecked(segment, 3, 4.toByte(), 5.toByte(), 6.toByte())
            context.setUnchecked(segment, 6, 7.toByte(), 8.toByte(), 9.toByte(), 10.toByte())
        }

        fun main() = 0
        """
    }

    @Test
    func sourceInterfaceAndMemberShapeMatchesPinnedViews() throws {
        try checkInterfaceAndMemberShape(library: false)
    }

    @Test
    func generatedKlibInterfaceAndMemberShapeMatchesPinnedViews() throws {
        try checkInterfaceAndMemberShape(library: true)
    }

    private func checkInterfaceAndMemberShape(library: Bool) throws {
        let expected = try index()
        try checkPinnedReferenceViews(expected)

        let ctx = try context(directConsumer(), library: library)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let fqNameParts = expected.interface.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) }
        let declarations = symbols.lookupAll(fqName: fqNameParts).compactMap { symbols.symbol($0) }
            .filter { $0.kind == .interface }
        try #require(declarations.count == 1, "Exactly one public interface declaration is expected")
        let type = try #require(declarations.first)
        let resolve: (InternedString) -> String = { ctx.interner.resolve($0) }
        let mangler = NameMangler()
        func encode(_ type: TypeID) -> String {
            mangler.encodeType(type, symbols: symbols, types: sema.types, nameResolver: resolve, unboxValueClasses: false)
        }
        func jvmType(_ signature: String) -> String {
            switch signature {
            case "Z", "B", "C", "S", "I", "J", "F", "D":
                return signature
            default:
                guard signature.hasPrefix("L"), signature.hasSuffix(";") else { return signature }
                let name = signature.dropFirst().dropLast().replacingOccurrences(of: ".", with: "/")
                return "L\(name);"
            }
        }
        func klibType(_ signature: String) -> String {
            switch signature {
            case "Z": return "kotlin/Boolean"
            case "B": return "kotlin/Byte"
            case "C": return "kotlin/Char"
            case "S": return "kotlin/Short"
            case "I": return "kotlin/Int"
            case "J": return "kotlin/Long"
            case "F": return "kotlin/Float"
            case "D": return "kotlin/Double"
            default:
                guard signature.hasPrefix("L"), signature.hasSuffix(";") else { return signature }
                let name = signature.dropFirst().dropLast().replacingOccurrences(of: ".", with: "/")
                return String(name)
            }
        }

        #expect(String(describing: type.visibility) == expected.interface.visibility)
        #expect(type.flags.contains(.abstractType) == library)
        #expect(!type.flags.contains(.sealedType) && !type.flags.contains(.funInterface))
        #expect(type.flags.contains(.importedLibrary) == library)
        #expect(symbols.directSupertypes(for: type.id).isEmpty == expected.interface.superFQNames.isEmpty)
        let annotations = symbols.annotations(for: type.id).filter {
            $0.annotationFQName != "kotlin.Metadata" && $0.annotationFQName != "kotlin.OptIn"
        }
        #expect(annotations.map(\.annotationFQName) == expected.interface.annotations)
        #expect(annotations.allSatisfy { $0.arguments.isEmpty && $0.useSiteTarget == nil })

        let children = symbols.children(of: type.id).compactMap { symbols.symbol($0) }
        let methods = children.filter { $0.kind == .function }
        try #require(children.count == expected.interface.members.count, "No extra interface declarations are expected")
        try #require(methods.count == expected.interface.members.count, "All declarations must be the four abstract methods")
        for member in expected.interface.members {
            let matches = methods.filter { candidate in
                guard resolve(candidate.name) == member.name,
                      let signature = symbols.functionSignature(for: candidate.id) else { return false }
                return signature.parameterTypes.map(encode) == member.parameterTypeSignatures
            }
            try #require(matches.count == 1, "Exact member overload is missing or duplicated: \(member.klibSignature)")
            let method = try #require(matches.first)
            let signature = try #require(symbols.functionSignature(for: method.id))
            #expect(String(describing: method.visibility) == "public")
            #expect(method.flags.contains(.abstractType) && !method.flags.contains(.overrideMember))
            #expect(method.flags.contains(.importedLibrary) == library)
            #expect(signature.parameterTypes.map(encode) == member.parameterTypeSignatures)
            #expect(encode(signature.returnType) == member.returnTypeSignature)
            let jvmDescriptor = "(\(signature.parameterTypes.map { jvmType(encode($0)) }.joined()))V"
            #expect(jvmDescriptor == member.jvmDescriptor)
            let klibParameters = signature.parameterTypes.map { klibType(encode($0)) }.joined(separator: ", ")
            #expect("abstract fun \(member.name)(\(klibParameters))" == member.klibSignature)
            #expect(signature.valueParameterSymbols.compactMap { symbols.symbol($0).map { resolve($0.name) } } == member.parameterNames)
            #expect(signature.valueParameterHasDefaultValues == Array(repeating: false, count: member.parameterNames.count))
            #expect(signature.valueParameterIsVararg == Array(repeating: false, count: member.parameterNames.count))
            #expect(
                signature.receiverType.map(encode) == "L\(expected.interface.fqName);",
                "A member dispatch receiver must match the declaring interface"
            )
            #expect(signature.typeParameterSymbols.isEmpty && !signature.isSuspend)
            #expect(!signature.canThrow)
            #expect(symbols.annotations(for: method.id).isEmpty)
        }

        if library {
            let artifact = try #require(ctx.options.stdlibLibraryPath)
            let records = MetadataDecoder().decode(try Data(contentsOf:
                URL(fileURLWithPath: artifact).appendingPathComponent("metadata.bin")
            ))
            let interfaceRecords = records.filter {
                $0.kind == .interface && $0.fqName == expected.interface.fqName
            }
            try #require(interfaceRecords.count == 1)
            let interfaceRecord = try #require(interfaceRecords.first)
            #expect(interfaceRecord.visibility == .public && interfaceRecord.modality == .abstract)
            #expect(!interfaceRecord.isSealedClass && !interfaceRecord.isFunInterface)
            #expect(interfaceRecord.superFQName == nil)
            #expect(
                interfaceRecord.annotations.map(\.annotationFQName).filter { $0 != "kotlin.Metadata" }
                    == expected.interface.annotations
            )

            let methodRecords = records.filter {
                $0.kind == .function && $0.fqName.hasPrefix(expected.interface.fqName + ".")
            }
            try #require(methodRecords.count == expected.interface.members.count)
            for member in expected.interface.members {
                let matching = methodRecords.filter {
                    $0.fqName.hasSuffix(".\(member.name)") && $0.valueParameterNames == member.parameterNames
                }
                try #require(matching.count == 1, "Generated KLIB member mismatch: \(member.klibSignature)")
                let record = try #require(matching.first)
                #expect(record.visibility == .public && record.modality == .abstract)
                #expect(!record.isOverride && !record.isInline && !record.isOperator && !record.isSuspend)
                #expect(!record.canThrow)
                #expect(record.valueParameterHasDefaultValues == Array(repeating: false, count: member.parameterNames.count))
                #expect(record.valueParameterIsVararg == Array(repeating: false, count: member.parameterNames.count))
                #expect(record.annotations.isEmpty)
            }
        }
    }

    @Test(arguments: [false, true])
    func interfaceUseRequiresUnsafeIoApiOptIn(library: Bool) throws {
        let source = """
        import kotlinx.io.unsafe.SegmentWriteContext
        fun rejected(context: SegmentWriteContext) = 0
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        let warnings = ctx.diagnostics.diagnostics.filter { $0.severity == .warning }
        #expect(warnings.count == 1, "One isolated unopted type use must warn: \(warnings)")
        #expect(warnings.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("UnsafeIoApi") })
    }

    private func checkPinnedReferenceViews(_ expected: ShapeIndex) throws {
        let upstream = repositoryRoot().appendingPathComponent("Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1")
        for (relativePath, block) in [
            (expected.apiPaths.jvm, expected.jvmInterfaceBlock),
            (expected.apiPaths.klib, expected.klibInterfaceBlock),
        ] {
            let source = String(decoding: try Data(contentsOf: upstream.appendingPathComponent(relativePath)), as: UTF8.self)
            let occurrences = source.components(separatedBy: block).count - 1
            #expect(occurrences == 1, "Pinned ABI block must occur once in \(relativePath)")
        }
        for member in expected.interface.members {
            let jvmLine = "\tpublic abstract fun \(member.name) \(member.jvmDescriptor)"
            #expect(expected.jvmInterfaceBlock.components(separatedBy: jvmLine).count - 1 == 1)
            #expect(expected.klibInterfaceBlock.components(separatedBy: member.klibSignature).count - 1 == 1)
        }
    }
}
