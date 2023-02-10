SkipFoundation
==============

# Implementation Status

This document lays out the structure of the CrossFoundation project, and provides the current implementation status of each major feature.


#### Table Key

##### Implementation Status
* _N/A_: There are no plans to port the given entity.
* _Unimplemented_: This entity does not yet exist.
* _Incomplete_: Implementation of this entity has begun, but critical sections have been left `NSUnimplemented()`
* _Mostly Complete_: All critical sections of this entity have been implemented, but some methods might remain `NSUnimplemented()`
* _Complete_: No methods are left `NSUnimplemented()` (though this is not a guarantee that work is complete -- there may be methods that need overriding or extra work)

##### Test Coverage
* _N/A_: This entity is internal and public tests are inappropriate, or it is an entity for which testing does not make sense
* _None_: There are no unit tests specific to this entity yet
* _Incomplete_: Unit tests exist for this entity, but there are critical paths that are not being tested
* _Substantial_: Most, if not all, of this entity's critical paths are being tested

There is no _Complete_ status for test coverage because there are always additional tests to be implemented. Even entities with _Substantial_ coverage are missing tests (e.g. `NSCoding` conformance, `NSCopying` conformance, `description`s, etc.)

### Entities

* **Model**: Representations for abstract model elements like null, data, and errors.

    | Entity Name              | Status          | Test Coverage | Notes                             |
    |--------------------------|-----------------|---------------|-----------------------------------|
    | `Data`                   | Incomplete      | Incomplete    |  `kotlin.ByteArray`               |
    | `NSData`                 | Incomplete      | "             |  "                                |
    | `NSMutableData`          | Incomplete      | "             |  "                                |
    | `UUID`                   | Incomplete      | Incomplete    |  `java.util.UUID`                 |
    | `NSUUID`                 | Incomplete      | "             |  "                                |
    | `NSNull`                 | Unimplemented   | None          |                                   |
    | `NSProgress`             | Unimplemented   | None          |                                   |
    | `NSError`                | Unimplemented   | None          |                                   |

* **DateTime**: Classes for representing dates, timezones, and calendars.

    | Entity Name        | Status          | Test Coverage | Notes                  |
    |--------------------|-----------------|---------------|------------------------|
    | `Date`             | Incomplete      | Incomplete    | `java.util.Date`       |
    | `NSDate`           | Incomplete      | "             | "                      |
    | `TimeZone`         | Unimplemented   | None          | `java.util.TimeZone`?  |
    | `NSTimeZone`       | Unimplemented   | None          | "                      |
    | `Calendar`         | Unimplemented   | None          | `java.util.Calendar`?  |
    | `NSCalendar`       | Unimplemented   | None          | "                      |
    | `DateComponents`   | Unimplemented   | None          |                        |
    | `NSDateComponents` | Unimplemented   | None          |                        |
    | `DateInterval`     | Unimplemented   | None          |                        |
    | `NSDateInterval`   | Unimplemented   | None          |                        |

* **App**: App runtime

    | Entity Name      | Status          | Test Coverage | Notes                                       |
    |------------------|-----------------|---------------|---------------------------------------------|
    | `NSPasteBoard`   | Unimplemented   | None          | `android.content.ClipboardManager`?         |
    | `NSCache`        | Unimplemented   | None          | `Map<SoftReference, V>`?                    |


* **UserDefaults**: A mechanism for storing values to persist as user settings and local.

    | Entity Name    | Status          | Test Coverage | Notes                                 |
    |----------------|-----------------|---------------|---------------------------------------|
    | `Locale`       | Incomplete      | Incomplete    | `java.util.Locale`                    |
    | `NSLocale`     | Incomplete      | "             | "                                     |
    | `UserDefaults` | Unimplemented   | None          | `android.content.SharedPreferences`?  |

* **URL**: Networking primitives

    The classes in this group provide functionality for manipulating URLs and paths via a common model object. The group also has classes for creating and receiving network connections.

    | Entity Name                  | Status          | Test Coverage | Notes                         |
    |------------------------------|-----------------|---------------|-------------------------------|
    | `URL`                        | Incomplete      | Incomplete    | `java.net.URL`                |
    | `NSURL`                      | Incomplete      | "             | "                             |
    | `URLRequest`                 | Unimplemented   | None          | `java.net.URLConnection`?     |
    | `NSURLRequest`               | Unimplemented   | None          | "                             |
    | `NSMutableURLRequest`        | Unimplemented   | None          | "                             |
    | `URLResponse`                | Unimplemented   | None          |                               |
    | `NSHTTPURLResponse`          | Unimplemented   | None          |                               |
    | `URLResourceValues`          | Unimplemented   | None          |                               |
    | `URLSession`                 | Unimplemented   | None          |                               |
    |  `URLSessionConfiguration`   | Unimplemented   | None          |                               |
    |  `URLSessionDelegate`        | Unimplemented   | None          |                               |
    |  `URLSessionTask`            | Unimplemented   | None          |                               |
    |  `URLSessionDataTask`        | Unimplemented   | None          |                               |
    |  `URLSessionUploadTask`      | Unimplemented   | None          |                               |
    |  `URLSessionDownloadTask`    | Unimplemented   | None          |                               |
    |  `URLSessionStreamTask`      | Unimplemented   | None          |                               |
    | `URLCache`                   | Unimplemented   | None          |                               |
    | `URLCredential`              | Unimplemented   | None          |                               |
    | `URLCredentialStorage`       | Unimplemented   | None          |                               |
    | `NSURLError*`                | Unimplemented   | None          |                               |
    | `URLProtectionSpace`         | Unimplemented   | None          |                               |
    | `URLProtocol`                | Unimplemented   | None          |                               |
    | `URLProtocolClient`          | Unimplemented   | None          |                               |
    | `NSURLQueryItem`             | Unimplemented   | None          |                               |
    | `URLResourceKey`             | Unimplemented   | None          |                               |
    | `URLFileResourceType`        | Unimplemented   | None          |                               |
    | `URLComponents`              | Unimplemented   | None          |                               |
    | `URLAuthenticationChallenge` | Unimplemented   | None          |                               |
    | `HTTPCookie`                 | Unimplemented   | None          |                               |
    | `HTTPCookiePropertyKey`      | Unimplemented   | None          |                               |
    | `HTTPCookieStorage`          | Unimplemented   | None          |                               |
    | `Host`                       | Unimplemented   | None          |                               |
    | `Configuration`              | Unimplemented   | None          |                               |
    | `HTTPBodySource`             | Unimplemented   | None          |                               |
    | `HTTPMessage`                | Unimplemented   | None          |                               |
    | `MultiHandle`                | Unimplemented   | None          |                               |
    | `TaskRegistry`               | Unimplemented   | None          |                               |
    | `TransferState`              | Unimplemented   | None          |                               |

* **Formatters**: Locale and language-correct formatted values.

    This group contains the base `NSFormatter` class and its subclasses. These formatters can be used for dates, numbers, sizes, energy, and many other types.

    | Entity Name                     | Status          | Test Coverage | Notes                         |
    |---------------------------------|-----------------|---------------|-------------------------------|
    | `ISO8601DateFormatter`          | Incomplete      | Incomplete    | `java.text.SimpleDateFormat`  |
    | `Formatter`                     | Unimplemented   | None          | uses pointers                 |
    | `NumberFormatter`               | Unimplemented   | None          | `java.text.NumberFormat`?     |
    | `DateFormatter`                 | Unimplemented   | None          | `java.text.DateFormat`?       |
    | `DateComponentsFormatter`       | Unimplemented   | None          |                               |
    | `DateIntervalFormatter`         | Unimplemented   | None          |                               |
    | `EnergyFormatter`               | Unimplemented   | None          |                               |
    | `LengthFormatter`               | Unimplemented   | None          |                               |
    | `MassFormatter`                 | Unimplemented   | None          |                               |
    | `ByteCountFormatter`            | Unimplemented   | None          |                               |
    | `MeasurementFormatter`          | Unimplemented   | None          |                               |
    | `PersonNameComponentsFormatter` | Unimplemented   | None          |                               |
    | `PersonNameComponents`          | Unimplemented   | None          |                               |
    | `NSPersonNameComponents`        | Unimplemented   | None          |                               |

* **OS**: Mechanisms for interacting with the operating system on a file system level as well as process and thread level

    | Entity Name      | Status          | Test Coverage | Notes                                       |
    |------------------|-----------------|---------------|---------------------------------------------|
    | `FileManager`    | Incomplete      | None          | `java.io.File`                              |
    | `Bundle`         | Unimplemented   | None          | `android.content.res.Resources`?            |
    | `FileHandle`     | Unimplemented   | None          | `java.io.FileDescriptor`?                   |
    | `Pipe`           | Unimplemented   | None          | `java.nio.channels.Pipe`?                   |
    | `Process`        | Unimplemented   | None          | `java.lang.Process`?                        |
    | `ProcessInfo`    | Unimplemented   | None          |                                             |
    | `Thread`         | Unimplemented   | None          | `java.lang.Thread`?                         |
    | `Operation`      | Unimplemented   | None          |                                             |
    | `BlockOperation` | Unimplemented   | None          |                                             |
    | `OperationQueue` | Unimplemented   | None          |                                             |
    | `Lock`           | Unimplemented   | None          | `java.util.concurrent.locks.Lock`?          |
    | `ConditionLock`  | Unimplemented   | None          |                                             |
    | `RecursiveLock`  | Unimplemented   | None          | `java.util.concurrent.locks.ReentrantLock`? |
    | `Condition`      | Unimplemented   | None          |                                             |

* **Runtime**: The basis for interoperability.

    The classes and methods in this group provide an interface for interoperability between C code and Swift. They also provide common layers used throughout the framework such as the root class `NSObject`.

    | Entity Name             | Status          | Test Coverage | Notes                        |
    |-------------------------|-----------------|---------------|------------------------------|
    | `NSObject`              | Unimplemented   | None          | `java.lang.Object`?          |
    | `NSStringFromClass`     | Unimplemented   | None          | `Class.getName`?             |
    | `NSClassFromString`     | Unimplemented   | None          | `Class.forName`?             |
    | `NSEnumerator`          | Unimplemented   | None          | `java.util.Enumeration`?     |
    | `NSGetSizeAndAlignment` | Unimplemented   | None          |                              |
    | `NSSwiftRuntime`        | Unimplemented   | None          |                              |
    | `Boxing`                | Unimplemented   | None          |                              |


* **Collections**: A group of classes to contain objects.

    The classes provided in this group provide basic collections. The primary role for these classes is to provide an interface layer between the CoreFoundation implementations and the standard library implementations. Additionally, they have useful extras like serialization support. There are also additional collection types that the standard library does not support.

     > _Note_: See [Known Issues](Issues.md) for more information about bridging between Foundation collection types and Swift standard library collection types.

    | Entity Name           | Status          | Test Coverage | Notes                          |
    |-----------------------|-----------------|---------------|--------------------------------|
    | `IndexPath`           | Unimplemented   | None          |                                |
    | `IndexSet`            | Unimplemented   | None          |                                |
    | `NSIndexSet`          | Unimplemented   | None          |                                |
    | `NSMutableIndexSet`   | Unimplemented   | None          |                                |
    | `NSOrderedSet`        | Unimplemented   | None          |                                |
    | `NSMutableOrderedSet` | Unimplemented   | None          |                                |
    | `NSDictionary`        | Unimplemented   | None          | `java.util.HashMap`            |
    | `NSMutableDictionary` | Unimplemented   | None          |                                |
    | `NSIndexPath`         | Unimplemented   | None          |                                |
    | `NSArray`             | Unimplemented   | None          | `java.util.ArrayList`?         |
    | `NSMutableArray`      | Unimplemented   | None          | "                              |
    | `NSSet`               | Unimplemented   | None          | `java.util.HashSet`            |
    | `NSMutableSet`        | Unimplemented   | None          | "                              |
    | `NSCountedSet`        | Unimplemented   | None          |                                |
    | `NSSortDescriptor`    | Unimplemented   | None          |                                |

* **Predicates**: Base functionality for building queries.

    This is the base class and subclasses for `NSPredicate` and `NSExpression`.

    | Entity Name             | Status        | Test Coverage | Notes                          |
    |-------------------------|---------------|---------------|--------------------------------|
    | `NSExpression`          | Unimplemented | None          |                                |
    | `NSComparisonPredicate` | Unimplemented | None          |                                |
    | `NSCompoundPredicate`   | Unimplemented | None          |                                |
    | `NSPredicate`           | Unimplemented | None          |                                |

* **RunLoop**: Timers, streams and run loops.

    The classes in this group provide support for scheduling work and acting upon input from external sources.

    | Entity Name      | Status          | Test Coverage | Notes                    |
    |------------------|-----------------|---------------|--------------------------|
    | `Stream`         | Unimplemented   | None          |                          |
    | `InputStream`    | Unimplemented   | None          | `java.io.InputStream`?   |
    | `NSInputStream`  | Unimplemented   | None          | "                        |
    | `NSOutputStream` | Unimplemented   | None          | `java.io.OutputStream`?  |
    | `NSStream`       | Unimplemented   | None          |                          |
    | `Port`           | Unimplemented   | None          |                          |
    | `MessagePort`    | Unimplemented   | None          |                          |
    | `SocketPort`     | Unimplemented   | None          |                          |
    | `PortMessage`    | Unimplemented   | None          |                          |
    | `RunLoop`        | Unimplemented   | None          |                          |
    | `Timer`          | Unimplemented   | None          |                          |

* **String**: A set of classes for scanning, manipulating and storing string values.

    The NSString implementation is present to provide an interface layer between CoreFoundation and Swift, but it also adds additional functionality on top of the Swift standard library String type. Other classes in this group provide mechanisms to scan, match regular expressions, store attributes in run arrays attached to strings, and represent sets of characters.

    > _Note_: See [Known Issues](Issues.md) for more information about bridging between the Foundation NSString types and Swift standard library String type.

    | Entity Name                 | Status          | Test Coverage | Notes                      |
    |-----------------------------|-----------------|---------------|----------------------------|
    | `NSRegularExpression`       | Unimplemented   | None          | `java.util.regex.Matcher`? |
    | `CharacterSet`              | Unimplemented   | None          |                            |
    | `NSCharacterSet`            | Unimplemented   | None          |                            |
    | `NSMutableCharacterSet`     | Unimplemented   | None          |                            |
    | `Scanner`                   | Unimplemented   | None          |                            |
    | `NSAttributedString`        | Unimplemented   | None          |                            |
    | `NSMutableAttributedString` | Unimplemented   | None          |                            |
    | `NSTextCheckingResult`      | Unimplemented   | None          |                            |
    | `NSString`                  | Unimplemented   | None          |                            |
    | `NSStringEncodings`         | Unimplemented   | None          |                            |
    | `NSStringAPI`               | Unimplemented   | None          |                            |
    | `ExtraStringAPIs`           | Unimplemented   | None          |                            |

* **Number**: A set of classes and methods for representing numeric values and structures.

    | Entity Name                       | Status          | Test Coverage | Notes                        |
    |-----------------------------------|-----------------|---------------|------------------------------|
    | `NSRange`                         | Unimplemented   | None          |                              |
    | `Decimal`                         | Unimplemented   | None          |                              |
    | `NSDecimalNumber`                 | Unimplemented   | None          |                              |
    | `NSDecimalNumberHandler`          | Unimplemented   | None          |                              |
    | `CGPoint`                         | Unimplemented   | None          |                              |
    | `CGSize`                          | Unimplemented   | None          |                              |
    | `CGRect`                          | Unimplemented   | None          |                              |
    | `NSEdgeInsets`                    | Unimplemented   | None          |                              |
    | `NSGeometry`                      | Unimplemented   | None          |                              |
    | `CGFloat`                         | Unimplemented   | None          |                              |
    | `AffineTransform`                 | Unimplemented   | None          |                              |
    | `NSAffineTransform`               | Unimplemented   | None          |                              |
    | `NSNumber`                        | Unimplemented   | None          |                              |
    | `NSConcreteValue`                 | Unimplemented   | None          |                              |
    | `NSSpecialValue`                  | Unimplemented   | None          |                              |
    | `NSValue`                         | Unimplemented   | None          |                              |
    | `Dimension`                       | Unimplemented   | None          |                              |
    
* **Measurement**: A set of classes and methods for handling measurement and conversions.

    | Entity Name                       | Status          | Test Coverage | Notes                        |
    |-----------------------------------|-----------------|---------------|------------------------------|
    | `Measurement`                     | Unimplemented   | None          |                              |
    | `NSMeasurement`                   | Unimplemented   | None          |                              |
    | `UnitConverter`                   | Unimplemented   | None          |                              |
    | `UnitConverterLinear`             | Unimplemented   | None          |                              |
    | `Unit`                            | Unimplemented   | None          |                              |
    | `UnitAcceleration`                | Unimplemented   | None          |                              |
    | `UnitAngle`                       | Unimplemented   | None          |                              |
    | `UnitArea`                        | Unimplemented   | None          |                              |
    | `UnitDispersion`                  | Unimplemented   | None          |                              |
    | `UnitDuration`                    | Unimplemented   | None          |                              |
    | `UnitEnergy`                      | Unimplemented   | None          |                              |
    | `UnitFrequency`                   | Unimplemented   | None          |                              |
    | `UnitFuelEfficiency`              | Unimplemented   | None          |                              |
    | `UnitLength`                      | Unimplemented   | None          |                              |
    | `UnitIlluminance`                 | Unimplemented   | None          |                              |
    | `UnitMass`                        | Unimplemented   | None          |                              |
    | `UnitPower`                       | Unimplemented   | None          |                              |
    | `UnitPressure`                    | Unimplemented   | None          |                              |
    | `UnitSpeed`                       | Unimplemented   | None          |                              |
    | `UnitTemperature`                 | Unimplemented   | None          |                              |
    | `UnitVolume`                      | Unimplemented   | None          |                              |

* **Notifications**: Classes for loosely coupling events from a set of many observers.

    | Entity Name          | Status          | Test Coverage | Notes                                  |
    |----------------------|-----------------|---------------|----------------------------------------|
    | `NSNotification`     | Unimplemented   | None          |                                        |
    | `NotificationCenter` | Unimplemented   | None          | `android.content.BroadcastReceiver`?   |
    | `Notification`       | Unimplemented   | None          |                                        |
    | `NotificationQueue`  | Unimplemented   | None          |                                        |

* **Serialization**: Serialization and deserialization functionality.

    The classes in this group perform tasks like parsing and writing JSON, property lists and binary archives.

    | Entity Name                 | Status          | Test Coverage | Notes                    |
    |-----------------------------|-----------------|---------------|--------------------------|
    | `NSJSONSerialization`       | Unimplemented   | None          | `kotlinx.serialization`? |
    | `PropertyListSerialization` | Unimplemented   | None          |                          |
    | `NSKeyedArchiver`           | Unimplemented   | None          |                          |
    | `NSKeyedCoderOldStyleArray` | Unimplemented   | None          |                          |
    | `NSKeyedUnarchiver`         | Unimplemented   | None          |                          |
    | `NSKeyedArchiverHelpers`    | Unimplemented   | None          |                          |
    | `NSCoder`                   | Unimplemented   | None          |                          |
    
* **XML**: A group of classes for parsing and representing XML documents and elements.

    The classes provided in this group are responsible for parsing and validating XML. They should be an interface for representing libxml2 in a more object-oriented manner.

    | Entity Name   | Status          | Test Coverage | Notes                                        |
    |---------------|-----------------|---------------|----------------------------------------------|
    | `XMLDocument` | Unimplemented   | None          | `org.w3c.dom.Document`?                      |
    | `XMLDTD`      | Unimplemented   | None          | `org.w3c.dom.DocumentType`?                  |
    | `XMLElement`  | Unimplemented   | None          | `org.w3c.dom.Element`?                       |
    | `XMLNode`     | Unimplemented   | None          | `org.w3c.dom.Node`?                          |
    | `XMLParser`   | Unimplemented   | None          | `javax.xml.parsers.SAXParserFactory`?        |
    | `XMLParser`+  | Unimplemented   | None          | `javax.xml.parsers.DocumentBuilderFactory`?  |
