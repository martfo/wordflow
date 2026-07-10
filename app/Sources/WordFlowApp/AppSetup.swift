// First-run scaffolding on the app side: create the data folder and write
// config.json (which the backend reads), distinct from Polenta's data (AC-10.3).

import Foundation
import WordFlowCore

enum AppSetup {
    static func dataDirectory() -> URL { RuntimeLocation.dataDirectory() }
    static func configPath() -> URL { dataDirectory().appendingPathComponent("config.json") }

    /// Ensure the data folder exists and config.json is present, then return the
    /// config path to hand the backend.
    @discardableResult
    static func ensure() -> URL {
        let data = dataDirectory()
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        let config = configPath()
        if !FileManager.default.fileExists(atPath: config.path) {
            let json: [String: Any] = [
                "data_path": data.path,
                "backend_port": 8770,
            ]
            if let bytes = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
                try? bytes.write(to: config)
            }
        }
        return config
    }
}
