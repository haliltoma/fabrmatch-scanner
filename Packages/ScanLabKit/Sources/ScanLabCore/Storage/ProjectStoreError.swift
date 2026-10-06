import Foundation

public enum ProjectStoreError: Error, Equatable {
    case notFound(UUID)
    case unsupportedSchema(found: Int, supported: Int)
    case invalidName
}
