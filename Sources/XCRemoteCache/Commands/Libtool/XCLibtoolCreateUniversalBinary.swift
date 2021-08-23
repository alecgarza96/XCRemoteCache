import Foundation

enum XCLibtoolCreateUniversalBinaryError: Error {
    ///  Missing ar libraries that should constitute an universal build
    case missingInputLibrary
}

/// Wrapper for `libtool` call for creating an universal binary
class XCLibtoolCreateUniversalBinary: XCLibtoolLogic {
    private let output: URL
    private let tempDir: URL
    private let firstInputURL: URL

    init(output: String, inputs: [String]) throws {
        self.output = URL(fileURLWithPath: output)
        guard let firstInput = inputs.first else {
            throw XCLibtoolCreateUniversalBinaryError.missingInputLibrary
        }
        let firstInputURL = URL(fileURLWithPath: firstInput)
        // inputs are place in $TARGET_TEMP_DIR/Objects-normal/$ARCH/Binary/$TARGET_NAME.a
        // TODO: find better (stable) technique to determine `$TARGET_TEMP_DIR`
        tempDir = firstInputURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        self.firstInputURL = firstInputURL
    }

    func run() {
        // check if RC is enabled. if so, take any input .a and copy to the output location
        let fileManager = FileManager.default
        let config: XCRemoteCacheConfig
        do {
            let srcRoot: URL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            config = try XCRemoteCacheConfigReader(srcRootPath: srcRoot.path, fileManager: fileManager)
                .readConfiguration()
        } catch {
            errorLog("Libtool initialization failed with error: \(error). Fallbacking to libtool")
            fallbackToDefault()
        }

        let markerURL = tempDir.appendingPathComponent(config.modeMarkerPath)
        do {
            let markerReader = FileMarkerReader(markerURL, fileManager: fileManager)
            guard markerReader.canRead() else {
                fallbackToDefault()
            }

            // Remote cache artifact stores a final library from DerivedData/Products location
            // (an universal binary here)
            // Fot a target where universal binary is used as a product, an output from single-architecture `xclibtool`
            // already is a universal library (the one from artifact package)
            // Link any of input libraries (here first) to the final output location because xclibtool flow ensures
            // that these are already an universal binary
            try fileManager.spt_forceLinkItem(at: firstInputURL, to: output)
        } catch {
            errorLog("Libtool failed with error: \(error). Fallbacking to libtool")
            do {
                try fileManager.removeItem(at: markerURL)
                fallbackToDefault()
            } catch {
                exit(1, "FATAL: libtool failed with error: \(error)")
            }
        }
    }

    private func fallbackToDefault() -> Never {
        let args = ProcessInfo().arguments
        let command = "libtool"
        let paramList = [command] + args.dropFirst()
        let cargs = paramList.map { strdup($0) } + [nil]
        execvp(command, cargs)

        /// C-function `execv` returns only when the command fails
        exit(1)
    }
}