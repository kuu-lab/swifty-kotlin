#if canImport(Testing)
    @testable import CompilerBackend
    @testable import CompilerCore
    @testable import CompilerTestSupport
    import Foundation
    import Testing

    struct SerializableDataClassKklibLayoutTests {
        @Test
        func generatedSerializerLayoutOnlyReferencesExportedProperties() throws {
            let librarySource = """
            package serialdemo

            import kotlinx.serialization.Serializable

            @Serializable
            data class D(val x: Int)
            """
            try withCompiledLibrary(source: librarySource, moduleName: "SerialDemo") { libraryPath in
                let metadata = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
                let records = MetadataDecoder().decode(metadata)
                var serializerSlots: String?
                var exportedProperties: Set<String> = []
                for record in records {
                    if record.fqName == "serialdemo.D.$serializer" {
                        serializerSlots = record.vtableSlots ?? ""
                    }
                    if record.kind == .property {
                        exportedProperties.insert(record.fqName)
                    }
                }
                let slots = try #require(serializerSlots)
                var missingAccessorTargets: [String] = []
                for entry in slots.split(separator: "|") {
                    let key = String(entry.split(separator: "@").first ?? "")
                    for prefix in ["v2:pget:", "v2:pset:", "pget:", "pset:"] where key.hasPrefix(prefix) {
                        let target = String(key.dropFirst(prefix.count))
                        if !exportedProperties.contains(target) {
                            missingAccessorTargets.append(target)
                        }
                    }
                }
                #expect(missingAccessorTargets.isEmpty, "\(missingAccessorTargets)")
            }
        }
    }
#endif
