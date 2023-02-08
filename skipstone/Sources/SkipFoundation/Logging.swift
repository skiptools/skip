#if !SKIP
import os

public typealias Logger = os.Logger
public typealias OSLogType = os.OSLogType
public typealias OSLogMessage = os.OSLogMessage
#else

// https://developer.android.com/reference/android/util/Log

// os.log.Logger to android.util.Log
// SKIP INSERT: import android.util.Log

/// In swift, this is a custom type that does lazy interpolation
public typealias OSLogMessage = String

// TODO: remove once we have constructors
// SKIP REPLACE: public class Logger(val subsystem: String, val category: String) { }
public final class Logger {
    public let subsystem: String
    public let category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }
}

// TODO: fix once we have enums
// SKIP REPLACE: public enum class OSLogType { default, info, debug, error, fault }
public enum OSLogType {
    case `default`
    case info
    case debug
    case error
    case fault
}

extension Logger {
    public func log(level: OSLogType, message: OSLogMessage) {
        if (level == OSLogType.default) {
            log(message)
        } else if (level == OSLogType.info) {
            info(message)
        } else if (level == OSLogType.debug) {
            debug(message)
        } else if (level == OSLogType.error) {
            error(message)
        } else if (level == OSLogType.fault) {
            fault(message)
        }
    }

    public func log(message: OSLogMessage) {
        Log.i(subsystem + "-" + category, message)
    }

    public func trace(message: OSLogMessage) {
        Log.v(subsystem + "-" + category, message)
    }

    public func debug(message: OSLogMessage) {
        Log.d(subsystem + "-" + category, message)
    }

    public func info(message: OSLogMessage) {
        Log.i(subsystem + "-" + category, message)
    }

    public func notice(message: OSLogMessage) {
        Log.i(subsystem + "-" + category, message)
    }

    public func warning(message: OSLogMessage) {
        Log.w(subsystem + "-" + category, message)
    }

    public func error(message: OSLogMessage) {
        Log.e(subsystem + "-" + category, message)
    }

    public func critical(message: OSLogMessage) {
        Log.wtf(subsystem + "-" + category, message)
    }

    public func fault(message: OSLogMessage) {
        Log.wtf(subsystem + "-" + category, message)
    }
}
#endif
