import AppKit
import WebKit

/// Hands a web tab's downloads to the system: saved into ~/Downloads (a unique name, marked as
/// downloaded from the web, like a browser's), and the Dock's Downloads stack bounces.
final class WebDownloads: NSObject, WKDownloadDelegate {
    private var sources: [ObjectIdentifier: URL] = [:]

    func adopt(_ download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        var destination = folder.appendingPathComponent(name)
        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        sources[ObjectIdentifier(download)] = response.url
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        let source = sources.removeValue(forKey: ObjectIdentifier(download))
        guard let file = download.progress.fileURL else { return }
        var values = URLResourceValues()
        var quarantine: [String: Any] = [kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
                                         kLSQuarantineAgentNameKey as String: "DEXMA"]
        if let source { quarantine[kLSQuarantineDataURLKey as String] = source }
        values.quarantineProperties = quarantine
        var url = file
        try? url.setResourceValues(values)
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"),
                                                     object: file.path)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        sources.removeValue(forKey: ObjectIdentifier(download))
    }
}
