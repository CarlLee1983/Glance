import Foundation

public enum DiskSpaceItemKind: Equatable, Sendable, Codable {
    case file
    case folder
}

public struct DiskSpaceSkippedPath: Equatable, Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.id = url.path
        self.url = url
        self.reason = reason
    }
}

public enum DiskSpaceScanState: Equatable, Sendable {
    case running
    case completed
    case cancelled
}
