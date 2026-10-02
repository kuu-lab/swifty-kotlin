import Foundation

extension DataFlowSemaPhase {
    /// A recognized Kotlin `.klib` library: validated manifest plus an open
    /// container that IR/metadata readers pull entries from.
    struct KlibModule {
        let path: String
        let uniqueName: String
        let manifest: KlibManifest
        let container: KlibContainer
    }

    /// Opens a `.klib` path (packed zip or unpacked directory), parses its
    /// manifest and applies the version gate. Declaration/body materialization
    /// happens in later stages of the pipeline; on success the module is
    /// returned for the caller to keep.
    func loadKlibModule(path: String, diagnostics: DiagnosticEngine) -> KlibModule? {
        let libName = URL(fileURLWithPath: path).lastPathComponent
        let container: KlibContainer
        let manifest: KlibManifest
        do {
            container = try KlibContainer(path: path)
            manifest = try container.manifest()
        } catch let error as KlibFormatError {
            switch error {
            case .missingManifest, .missingManifestKey, .invalidKlibLayout,
                 .entryNotFound:
                diagnostics.error(
                    "KSWIFTK-LIB-0026",
                    "Invalid manifest in \(libName): \(error)",
                    range: nil
                )
            default:
                diagnostics.error(
                    "KSWIFTK-LIB-0025",
                    "Cannot read klib container \(libName): \(error)",
                    range: nil
                )
            }
            return nil
        } catch {
            diagnostics.error(
                "KSWIFTK-LIB-0025",
                "Cannot read klib container \(libName): \(error.localizedDescription)",
                range: nil
            )
            return nil
        }

        switch manifest.compatibility {
        case .supported:
            break
        case .bestEffort(let reason):
            diagnostics.warning("KSWIFTK-LIB-0027", reason, range: nil)
        case .unsupported(let reason):
            diagnostics.error("KSWIFTK-LIB-0027", reason, range: nil)
            return nil
        }

        diagnostics.warning(
            "KSWIFTK-LIB-0028",
            "Kotlin library \(libName) (module '\(manifest.uniqueName)') recognized; "
                + "declaration import is not yet implemented",
            range: nil
        )
        return KlibModule(
            path: path,
            uniqueName: manifest.uniqueName,
            manifest: manifest,
            container: container
        )
    }
}
