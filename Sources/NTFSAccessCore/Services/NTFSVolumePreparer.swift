import Foundation

enum NTFSVolumePreparer {

    /// Best-effort `ntfsfix -d` before mount (clears Windows dirty flag).
    static func ntfsfixStep(device: String, ntfsfix: String?) -> String {
        guard let ntfsfix, !ntfsfix.isEmpty else { return "" }
        let qDevice = ProcessRunner.shellQuote(device)
        let qNtfsfix = ProcessRunner.shellQuote(ntfsfix)
        return "\(qNtfsfix) -d \(qDevice) >/dev/null 2>&1 || true; "
    }

    static func companionTool(named name: String, beside ntfs3g: String) -> String? {
        let dir = (ntfs3g as NSString).deletingLastPathComponent
        let path = "\(dir)/\(name)"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
