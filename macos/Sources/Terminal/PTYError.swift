import Foundation

enum PTYError: Error, Equatable {
    case invalidExecutable
    case invalidWorkingDirectory
    case launchFailed(Int32)
    case closed
    case writeFailed(Int32)
    case resizeFailed(Int32)
}
