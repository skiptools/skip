#if canImport(FoundationNetworking)
import FoundationNetworking
import Foundation

// Non-Darwin (e.g., Linux) do not yet support async URLSession functions, so we re-create them here
// https://github.com/apple/swift-corelibs-foundation/issues/3205
extension URLSession {
    /// TODO: implement delegate for Linux
    public typealias URLSessionTaskDelegate = Void

    public func data(for request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        try await fetch(request: request, validate: nil)
    }

    public func data(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url), delegate: delegate)
    }

    public func download(from request: URLRequest, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse) {
        try await downloadRequest(for: request)
    }

    public func download(from url: URL, delegate: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse) {
        try await download(from: URLRequest(url: url), delegate: delegate)
    }


    /// Fetches the given request asynchronously, optionally validating that the response code is within the given range of HTTP codes.
    internal func fetch(request: URLRequest, validate codes: IndexSet? = IndexSet(200..<300)) async throws -> (data: Data, response: URLResponse) {
        return try await fetchRequest(request: request, validate: codes)
    }

    private func fetchRequest(request: URLRequest, validate codes: IndexSet?) async throws -> (data: Data, response: URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            dataTask(with: request) { data, response, error in
                if let data = data, let response = response, error == nil {
                    do {
                        let validResponse = try response.validating(codes: codes)
                        continuation.resume(returning: (data, validResponse))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileNoSuchFile))
                }
            }.resume()
        }
    }

    /// Downloads the given file. It should behave the same as the async URLSession.download function (which is missing from linux).
    private func downloadRequest(for request: URLRequest, useContentDispositionFileName: Bool = true, useLastModifiedDate: Bool = true) async throws -> (localURL: URL, response: URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            downloadTaskCopy(with: request, useContentDispositionFileName: useContentDispositionFileName, useLastModifiedDate: useLastModifiedDate) { url, response, error in
                if let url = url, let response = response, error == nil {
                    continuation.resume(returning: (url, response))
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
            .resume()
        }
    }

    /// If the download from `downloadTask` is successful, the completion handler receives a URL indicating the location of the downloaded file on the local filesystem. This storage is temporary. To preserve the file, this will move it from the temporary location before returning from the completion handler.
    /// In practice, macOS seems to be inconsistent in when it ever cleans up these files, so a failure here will manifest itself in occasional missing files.
    /// This is needed for running an async operation that will still have access to the resulting file.
    /// - Parameters:
    ///   - request: the request for the download
    ///   - useContentDispositionFileName: whether to attempt to rename the file based on the file name specified in the `Content-Disposition` header, if present.
    ///   - useLastModifiedDate: whether to transfer the server's reported "Last-Modified" header to set the creation time of the file.
    ///   - completionHandler: the handler to invoke when the download is complete
    /// - Returns: the task that was initiated
    func downloadTaskCopy(with request: URLRequest, useContentDispositionFileName: Bool = true, useLastModifiedDate: Bool = true, completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void) -> URLSessionDownloadTask {
        self.downloadTask(with: request) { url, response, error in
            /// Files are generally placed somewhere like: file:///var/folders/24/8k48jl6d249_n_qfxwsl6xvm0000gn/T/CFNetworkDownload_q0k6gM.tmp
            do {
                /// We'll copy it to a temporary replacement directory with the base name matching the URL's name
                if let temporaryLocalURL = url,
                   temporaryLocalURL.isFileURL {
                    var pathName = temporaryLocalURL.lastPathComponent

                    if useContentDispositionFileName == true,
                       let disposition = (response as? HTTPURLResponse)?.allHeaderFields["Content-Disposition"] as? String,
                       disposition.hasPrefix("attachment; filename="),
                       let contentDispositionFileName = disposition.components(separatedBy: "filename=").last,
                       contentDispositionFileName.unicodeScalars.filter(CharacterSet.urlPathAllowed.inverted.contains).isEmpty,
                       contentDispositionFileName.contains("/") == false {
                         pathName = contentDispositionFileName
                     }

                    let tempDir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: temporaryLocalURL, create: true)
                     let destinationURL = tempDir.appendingPathComponent(pathName)
                     try FileManager.default.moveItem(at: temporaryLocalURL, to: destinationURL)

                     if useLastModifiedDate == true, let lastModifiedDate = response?.lastModifiedDate {
                         // preserve Last-Modified by transferring the date to the item
                         try? FileManager.default.setAttributes([.creationDate : lastModifiedDate, .modificationDate : lastModifiedDate], ofItemAtPath: destinationURL.path)
                     }

                     //print("replace download file for:", response?.url, "local:", temporaryLocalURL.path, "moved:", destinationURL.path, (try? destinationURL.self.resourceValues(forKeys: [.fileSizeKey]).fileSize)?.localizedByteCount())
                     return completionHandler(destinationURL, response, error)
                }
            } catch {
                //print("ignoring file move error and falling back to un-copied file:", error)
            }

            // fall-back to the completion handler
            return completionHandler(url, response, error)
        }
    }

}

extension URLResponse {
    private static let gmtDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
        return fmt
    }()

    /// Returns the last modified date for this response
    public var lastModifiedDate: Date? {
        guard let headers = (self as? HTTPURLResponse)?.allHeaderFields else {
            return nil
        }
        guard let modDate = headers["Last-Modified"] as? String else {
            return nil
        }
        return Self.gmtDateFormatter.date(from: modDate)
    }

    /// Attempts to validate the status code in the given range and throws an error if they fail.
    func validating(codes: IndexSet?) throws -> Self {
        guard let codes = codes else {
            return self // no validation
        }

        guard let httpResponse = self as? HTTPURLResponse else {
            // loading from the file system doesn't expose codes
            return self // throw URLError(.badServerResponse)
        }

        if !codes.contains(httpResponse.statusCode) {
            throw InvalidHTTPCode(code: httpResponse.statusCode)
        }

        return self // the response is valid
    }

    public struct InvalidHTTPCode : Error, LocalizedError {
        public let code: Int

        public var errorDescription: String? {
            "Invalid HTTP Response: \(code)"
        }
    }

}

extension URL {
    public func appending(path: String) -> URL {
        appendingPathComponent(path)
    }
}

#endif
