#if !SKIP
import class Foundation.FileManager
public typealias FileManager = Foundation.FileManager
public typealias PlatformFileManager = Foundation.FileManager
#else

/// An interface to the file system compatible with ``Foundation.FileManager``
public final class FileManager {
    /// Returns the shared single file manager
    public static var `default` = FileManager()

    public func removeItem(atPath path: String) throws {
        if (java.io.File(path).delete() != true) {
            throw UnableToDeleteFileError(path = path)
        }
    }

    public func removeItem(atPath url: URL) throws {
        if (java.io.File(url.path).delete() != true) {
            throw UnableToDeleteFileError(path = url.path)
        }
    }

    // SKIP REPLACE: data class UnableToDeleteFileError(val path: String) : java.io.IOException() { }
    struct UnableToDeleteFileError : java.io.IOException {
        let path: String
    }
}


/// The system temporary folder
public func NSTemporaryDirectory() -> String {
    return java.lang.System.getProperty("java.io.tmpdir")
}

/// The user's home directory.
public func NSHomeDirectory() -> String {
    return java.lang.System.getProperty("user.home")
}

/// The current user name.
public func NSUserName() -> String {
    return java.lang.System.getProperty("user.name")
}

#endif
