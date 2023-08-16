// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import protocol Foundation.LocalizedError
import class Foundation.NSError

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(CRT)
import CRT
#elseif canImport(WASILibc)
import WASILibc
#endif

#if os(Windows)
import func WinSDK.GetStdHandle
import func WinSDK.GetConsoleScreenBufferInfo
import let WinSDK.ERROR_BAD_ARGUMENTS
import let WinSDK.STD_OUTPUT_HANDLE
import struct WinSDK.CONSOLE_SCREEN_BUFFER_INFO
#endif

// The following code is mostly derived from https://github.com/apple/swift-argument-parser/archive/refs/tags/1.2.3.zip
// with some non-essential functionality (like shell detection and completion generation) removed.
// The license for the source of the derived code is as follows:

//===----------------------------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Argument Parser open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//


// MARK: Parsing

/// A previously decoded parsable arguments type.
///
/// Because arguments are consumed and decoded the first time they're
/// encountered, we save the decoded instances for using later in the
/// command/subcommand hierarchy.
struct DecodedArguments {
  var type: ParsableArguments.Type
  var value: ParsableArguments

  var commandType: ParsableCommand.Type? {
    type as? ParsableCommand.Type
  }

  var command: ParsableCommand? {
    value as? ParsableCommand
  }
}

/// A decoder that decodes from parsed command-line arguments.
final class ArgumentDecoder: Decoder {
  init(values: ParsedValues, previouslyDecoded: [DecodedArguments] = []) {
    self.values = values
    self.previouslyDecoded = previouslyDecoded
    self.usedOrigins = InputOrigin()
  }

  let values: ParsedValues
  var usedOrigins: InputOrigin
  var nextCommandIndex = 0
  var previouslyDecoded: [DecodedArguments] = []

  var codingPath: [CodingKey] = []

  var userInfo: [CodingUserInfoKey : Any] = [:]

  func container<K>(keyedBy type: K.Type) throws -> KeyedDecodingContainer<K> where K: CodingKey {
    let container = ParsedArgumentsContainer(for: self, keyType: K.self, codingPath: codingPath)
    return KeyedDecodingContainer(container)
  }

  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    throw Error.topLevelHasNoUnkeyedContainer
  }

  func singleValueContainer() throws -> SingleValueDecodingContainer {
    throw Error.topLevelHasNoSingleValueContainer
  }
}

extension ArgumentDecoder {
  fileprivate func element(forKey key: InputKey) -> ParsedValues.Element? {
    guard let element = values.element(forKey: key) else { return nil }
    usedOrigins.formUnion(element.inputOrigin)
    return element
  }
}

extension ArgumentDecoder {
  enum Error: Swift.Error {
    case topLevelHasNoUnkeyedContainer
    case topLevelHasNoSingleValueContainer
    case singleValueDecoderHasNoContainer
    case wrongKeyType(CodingKey.Type, CodingKey.Type)
  }
}

final class ParsedArgumentsContainer<K>: KeyedDecodingContainerProtocol where K : CodingKey {
  var codingPath: [CodingKey]

  let decoder: ArgumentDecoder

  init(for decoder: ArgumentDecoder, keyType: K.Type, codingPath: [CodingKey]) {
    self.codingPath = codingPath
    self.decoder = decoder
  }

  var allKeys: [K] {
    fatalError()
  }

  fileprivate func element(forKey key: K) -> ParsedValues.Element? {
    let k = InputKey(codingKey: key, path: codingPath)
    return decoder.element(forKey: k)
  }

  func contains(_ key: K) -> Bool {
    return element(forKey: key) != nil
  }

  func decodeNil(forKey key: K) throws -> Bool {
    return element(forKey: key)?.value == nil
  }

  func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T : Decodable {
    let parsedElement = element(forKey: key)
    if parsedElement?.inputOrigin.isDefaultValue ?? false, let rawValue = parsedElement?.value {
      guard let value = rawValue as? T else {
        throw InternalParseError.wrongType(rawValue, forKey: parsedElement!.key)
      }
      return value
    }
    let subDecoder = SingleValueDecoder(userInfo: decoder.userInfo, underlying: decoder, codingPath: codingPath + [key], key: InputKey(codingKey: key, path: codingPath), parsedElement: element(forKey: key))
    return try type.init(from: subDecoder)
  }

  func decodeIfPresent<T>(_ type: T.Type, forKey key: KeyedDecodingContainer<K>.Key) throws -> T? where T : Decodable {
    let parsedElement = element(forKey: key)
    if let parsedElement = parsedElement, parsedElement.inputOrigin.isDefaultValue {
      return parsedElement.value as? T
    }
    let subDecoder = SingleValueDecoder(userInfo: decoder.userInfo, underlying: decoder, codingPath: codingPath + [key], key: InputKey(codingKey: key, path: codingPath), parsedElement: parsedElement)
    do {
      return try type.init(from: subDecoder)
    } catch let error as ParserError {
      if case .noValue = error {
        return nil
      } else {
        throw error
      }
    }
  }

  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
    fatalError()
  }

  func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
    fatalError()
  }

  func superDecoder() throws -> Decoder {
    fatalError()
  }

  func superDecoder(forKey key: K) throws -> Decoder {
    fatalError()
  }
}

struct SingleValueDecoder: Decoder {
  var userInfo: [CodingUserInfoKey : Any]
  var underlying: ArgumentDecoder
  var codingPath: [CodingKey]
  var key: InputKey
  var parsedElement: ParsedValues.Element?

  func container<K>(keyedBy type: K.Type) throws -> KeyedDecodingContainer<K> where K: CodingKey {
    return KeyedDecodingContainer(ParsedArgumentsContainer(for: underlying, keyType: type, codingPath: codingPath))
  }

  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    guard let e = parsedElement else {
      var errorPath = codingPath
      let last = errorPath.popLast()!
      throw ParserError.noValue(forKey: InputKey(codingKey: last, path: errorPath))
    }
    guard let a = e.value as? [Any] else {
      throw ParserError.invalidState
    }
    return UnkeyedContainer(codingPath: codingPath, parsedElement: e, array: ArrayWrapper(a))
  }

  func singleValueContainer() throws -> SingleValueDecodingContainer {
    return SingleValueContainer(underlying: self, codingPath: codingPath, parsedElement: parsedElement)
  }

  func previousValue<T>(_ type: T.Type) throws -> T {
    guard let previous = underlying.previouslyDecoded.first(where: { type == $0.type })
      else { throw ParserError.invalidState }
    return previous.value as! T
  }

  func saveValue<T: ParsableArguments>(_ value: T, type: T.Type = T.self) {
    underlying.previouslyDecoded.append(DecodedArguments(type: type, value: value))
  }

  struct SingleValueContainer: SingleValueDecodingContainer {
    var underlying: SingleValueDecoder
    var codingPath: [CodingKey]
    var parsedElement: ParsedValues.Element?

    func decodeNil() -> Bool {
      return parsedElement == nil
    }

    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
      guard let e = parsedElement else {
        var errorPath = codingPath
        let last = errorPath.popLast()!
        throw ParserError.noValue(forKey: InputKey(codingKey: last, path: errorPath))
      }
      guard let s = e.value as? T else {
        throw InternalParseError.wrongType(e.value, forKey: e.key)
      }
      return s
    }
  }

  struct UnkeyedContainer: UnkeyedDecodingContainer {
    var codingPath: [CodingKey]
    var parsedElement: ParsedValues.Element
    var array: ArrayWrapperProtocol

    var count: Int? {
      return array.count
    }

    var isAtEnd: Bool {
      return array.isAtEnd
    }

    var currentIndex: Int {
      return array.currentIndex
    }

    mutating func decodeNil() throws -> Bool {
      return false
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
      guard let next = array.getNext() else { fatalError() }
      guard let t = next as? T else {
        throw InternalParseError.wrongType(next, forKey: parsedElement.key)
      }
      return t
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
      fatalError()
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
      fatalError()
    }

    mutating func superDecoder() throws -> Decoder {
      fatalError()
    }
  }
}

/// A type-erasing wrapper for consuming elements of an array.
protocol ArrayWrapperProtocol {
  var count: Int? { get }
  var isAtEnd: Bool { get }
  var currentIndex: Int { get }
  mutating func getNext() -> Any?
}

struct ArrayWrapper<A>: ArrayWrapperProtocol {
  var base: [A]
  var currentIndex: Int

  init(_ a: [A]) {
    self.base = a
    self.currentIndex = a.startIndex
  }

  var count: Int? {
    return base.count
  }

  var isAtEnd: Bool {
    return base.endIndex <= currentIndex
  }

  mutating func getNext() -> Any? {
    guard currentIndex < base.endIndex else { return nil }
    let next = base[currentIndex]
    currentIndex += 1
    return next
  }
}

struct ArgumentDefinition {
  /// A closure that modifies a `ParsedValues` instance to include this
  /// argument's value.
  enum Update {
    typealias Nullary = (InputOrigin, Name?, inout ParsedValues) throws -> Void
    typealias Unary = (InputOrigin, Name?, String, inout ParsedValues) throws -> Void

    /// An argument that gets its value solely from its presence.
    case nullary(Nullary)

    /// An argument that takes a string as its value.
    case unary(Unary)
  }

  typealias Initial = (InputOrigin, inout ParsedValues) throws -> Void

  enum Kind {
    /// An option or flag, with a name and an optional value.
    case named([Name])

    /// A positional argument.
    case positional

    /// A pseudo-argument that takes its value from a property's default value
    /// instead of from command-line arguments.
    case `default`
  }

  struct Help {
    struct Options: OptionSet {
      var rawValue: UInt

      static let isOptional = Options(rawValue: 1 << 0)
      static let isRepeating = Options(rawValue: 1 << 1)
    }

    var options: Options
    var defaultValue: String?
    var keys: [InputKey]
    var allValues: [String]
    var isComposite: Bool
    var abstract: String
    var discussion: String
    var valueName: String
    var visibility: ArgumentVisibility
    var parentTitle: String

    init(
      allValues: [String],
      options: Options,
      help: ArgumentHelp?,
      defaultValue: String?,
      key: InputKey,
      isComposite: Bool
    ) {
      self.options = options
      self.defaultValue = defaultValue
      self.keys = [key]
      self.allValues = allValues
      self.isComposite = isComposite
      self.abstract = help?.abstract ?? ""
      self.discussion = help?.discussion ?? ""
      self.valueName = help?.valueName ?? ""
      self.visibility = help?.visibility ?? .default
      self.parentTitle = ""
    }
  }

  /// This folds the public `ArrayParsingStrategy` and `SingleValueParsingStrategy`
  /// into a single enum.
  enum ParsingStrategy {
    /// Expect the next `SplitArguments.Element` to be a value and parse it.
    /// Will fail if the next input is an option.
    case `default`
    /// Parse the next `SplitArguments.Element.value`
    case scanningForValue
    /// Parse the next `SplitArguments.Element` as a value, regardless of its type.
    case unconditional
    /// Parse multiple `SplitArguments.Element.value` up to the next non-`.value`
    case upToNextOption
    /// Parse all remaining `SplitArguments.Element` as values, regardless of its type.
    case allRemainingInput
    /// Collect all the elements after the terminator, preventing them from
    /// appearing in any other position.
    case postTerminator
    /// Collect all unused inputs once recognized arguments/options/flags have
    /// been parsed.
    case allUnrecognized
  }

  var kind: Kind
  var help: Help
  var completion: CompletionKind
  var parsingStrategy: ParsingStrategy
  var update: Update
  var initial: Initial

  var names: [Name] {
    switch kind {
    case .named(let n): return n
    case .positional, .default: return []
    }
  }

  var valueName: String {
    help.valueName.mapEmpty {
      names.preferredName?.valueString
        ?? help.keys.first?.name.convertedToSnakeCase(separator: "-")
        ?? "value"
    }
  }

  init(
    kind: Kind,
    help: Help,
    completion: CompletionKind,
    parsingStrategy: ParsingStrategy = .default,
    update: Update,
    initial: @escaping Initial = { _, _ in }
  ) {
    if case (.positional, .nullary) = (kind, update) {
      preconditionFailure("Can't create a nullary positional argument.")
    }

    self.kind = kind
    self.help = help
    self.completion = completion
    self.parsingStrategy = parsingStrategy
    self.update = update
    self.initial = initial
  }
}

extension ArgumentDefinition: CustomDebugStringConvertible {
  var debugDescription: String {
    switch (kind, update) {
    case (.named(let names), .nullary):
      return names
        .map { $0.synopsisString }
        .joined(separator: ",")
    case (.named(let names), .unary):
      return names
        .map { $0.synopsisString }
        .joined(separator: ",")
        + " <\(valueName)>"
    case (.positional, _):
      return "<\(valueName)>"
    case (.default, _):
      return ""
    }
  }
}

extension ArgumentDefinition {
  var optional: ArgumentDefinition {
    var result = self
    result.help.options.insert(.isOptional)
    return result
  }

  var nonOptional: ArgumentDefinition {
    var result = self
    result.help.options.remove(.isOptional)
    return result
  }
}

extension ArgumentDefinition {
  var isPositional: Bool {
    if case .positional = kind {
      return true
    }
    return false
  }

  var isRepeatingPositional: Bool {
    isPositional && help.options.contains(.isRepeating)
  }

  var isNullary: Bool {
    if case .nullary = update {
      return true
    } else {
      return false
    }
  }

  var allowsJoinedValue: Bool {
    names.contains(where: { $0.allowsJoined })
  }
}

extension ArgumentDefinition.Kind {
  static func name(key: InputKey, specification: NameSpecification) -> ArgumentDefinition.Kind {
    let names = specification.makeNames(key)
    return ArgumentDefinition.Kind.named(names)
  }
}


// MARK: - Common @Argument, @Option, Unparsed Initializer Path
extension ArgumentDefinition {
  // MARK: Unparsed Keys
  /// Creates an argument definition for a property that isn't parsed from the
  /// command line.
  ///
  /// This initializer is used for any property defined on a `ParsableArguments`
  /// type that isn't decorated with one of ArgumentParser's property wrappers.
  init(unparsedKey: String, default defaultValue: Any?, parent: InputKey?) {
    self.init(
      container: Bare<Any>.self,
      key: InputKey(name: unparsedKey, parent: parent),
      kind: .default,
      allValues: [],
      help: .private,
      defaultValueDescription: nil,
      parsingStrategy: .default,
      parser: { (key, origin, name, valueString) in
        throw ParserError.unableToParseValue(
          origin, name, valueString, forKey: key, originalError: nil)
      },
      initial: defaultValue,
      completion: nil)
  }

  init<Container>(
    container: Container.Type,
    key: InputKey,
    kind: ArgumentDefinition.Kind,
    help: ArgumentHelp?,
    parsingStrategy: ParsingStrategy,
    initial: Container.Initial?,
    completion: CompletionKind?
  ) where Container: ArgumentDefinitionContainerExpressibleByArgument {
    self.init(
      container: Container.self,
      key: key,
      kind: kind,
      allValues: Container.Contained.allValueStrings,
      help: help,
      defaultValueDescription: Container.defaultValueDescription(initial),
      parsingStrategy: parsingStrategy,
      parser: { (key, origin, name, valueString) -> Container.Contained in
        guard let value = Container.Contained(argument: valueString) else {
          throw ParserError.unableToParseValue(
            origin, name, valueString, forKey: key, originalError: nil)
        }
        return value
      },
      initial: initial,
      completion: completion ?? Container.Contained.defaultCompletionKind)
  }

  init<Container>(
    container: Container.Type,
    key: InputKey,
    kind: ArgumentDefinition.Kind,
    help: ArgumentHelp?,
    parsingStrategy: ParsingStrategy,
    transform: @escaping (String) throws -> Container.Contained,
    initial: Container.Initial?,
    completion: CompletionKind?
  ) where Container: ArgumentDefinitionContainer {
    self.init(
      container: Container.self,
      key: key,
      kind: kind,
      allValues: [],
      help: help,
      defaultValueDescription: nil,
      parsingStrategy: parsingStrategy,
      parser: { (key, origin, name, valueString) -> Container.Contained in
        do {
          return try transform(valueString)
        } catch {
          throw ParserError.unableToParseValue(
            origin, name, valueString, forKey: key, originalError: error)
        }
      },
      initial: initial,
      completion: completion)
  }

  private init<Container>(
    container: Container.Type,
    key: InputKey,
    kind: ArgumentDefinition.Kind,
    allValues: [String],
    help: ArgumentHelp?,
    defaultValueDescription: String?,
    parsingStrategy: ParsingStrategy,
    parser: @escaping (InputKey, InputOrigin, Name?, String) throws -> Container.Contained,
    initial: Container.Initial?,
    completion: CompletionKind?
  ) where Container: ArgumentDefinitionContainer {
    self.init(
      kind: kind,
      help: .init(
        allValues: allValues,
        options: Container.helpOptions.union(initial != nil ? [.isOptional] : []),
        help: help,
        defaultValue: defaultValueDescription,
        key: key,
        isComposite: false),
      completion: completion ?? .default,
      parsingStrategy: parsingStrategy,
      update: .unary({ (origin, name, valueString, parsedValues) in
        let value = try parser(key, origin, name, valueString)
        Container.update(
          parsedValues: &parsedValues,
          value: value,
          key: key,
          origin: origin)
      }),
      initial: { origin, values in
        let inputOrigin: InputOrigin
        switch kind {
        case .default:
          inputOrigin = InputOrigin(element: .defaultValue)
        case .named, .positional:
          inputOrigin = origin
        }
        values.set(initial, forKey: key, inputOrigin: inputOrigin)
      })
  }
}

// MARK: - Abstraction over T, Option<T>, Array<T>
protocol ArgumentDefinitionContainer {
  associatedtype Contained
  associatedtype Initial

  static var helpOptions: ArgumentDefinition.Help.Options { get }
  static func update(
    parsedValues: inout ParsedValues,
    value: Contained,
    key: InputKey,
    origin: InputOrigin)
}

protocol ArgumentDefinitionContainerExpressibleByArgument:
  ArgumentDefinitionContainer where Contained: ExpressibleByArgument {
  static func defaultValueDescription(_ initial: Initial?) -> String?
}

enum Bare<T> { }

extension Bare: ArgumentDefinitionContainer {
  typealias Contained = T
  typealias Initial = T

  static var helpOptions: ArgumentDefinition.Help.Options { [] }

  static func update(
    parsedValues: inout ParsedValues,
    value: Contained,
    key: InputKey,
    origin: InputOrigin
  ) {
    parsedValues.set(value, forKey: key, inputOrigin: origin)
  }
}

extension Bare: ArgumentDefinitionContainerExpressibleByArgument
where Contained: ExpressibleByArgument {
  static func defaultValueDescription(_ initial: T?) -> String? {
    guard let initial = initial else { return nil }
    return initial.defaultValueDescription
  }
}

extension Optional: ArgumentDefinitionContainer {
  typealias Contained = Wrapped
  typealias Initial = Wrapped

  static var helpOptions: ArgumentDefinition.Help.Options { [.isOptional] }

  static func update(
    parsedValues: inout ParsedValues,
    value: Contained,
    key: InputKey,
    origin: InputOrigin
  ) {
    parsedValues.set(value, forKey: key, inputOrigin: origin)
  }
}

extension Optional: ArgumentDefinitionContainerExpressibleByArgument
where Contained: ExpressibleByArgument {
  static func defaultValueDescription(_ initial: Initial?) -> String? {
    guard let initial = initial else { return nil }
    return initial.defaultValueDescription
  }
}

extension Array: ArgumentDefinitionContainer {
  typealias Contained = Element
  typealias Initial = Array<Element>

  static var helpOptions: ArgumentDefinition.Help.Options { [.isRepeating] }

  static func update(
    parsedValues: inout ParsedValues,
    value: Element,
    key: InputKey,
    origin: InputOrigin
  ) {
    parsedValues.update(
      forKey: key,
      inputOrigin: origin,
      initial: .init(),
      closure: { $0.append(value) })
  }
}

extension Array: ArgumentDefinitionContainerExpressibleByArgument
where Element: ExpressibleByArgument {
  static func defaultValueDescription(_ initial: Array<Element>?) -> String? {
    guard let initial = initial else { return nil }
    guard !initial.isEmpty else { return nil }
    return initial
      .lazy
      .map { $0.defaultValueDescription }
      .joined(separator: ", ")
  }
}

/// A nested tree of argument definitions.
///
/// The main reason for having a nested representation is to build help output.
/// For output like:
///
///     Usage: mytool [-v | -f] <input> <output>
///
/// The `-v | -f` part is one *set* that’s optional, `<input> <output>` is
/// another. Both of these can then be combined into a third set.
struct ArgumentSet {
  var content: [ArgumentDefinition] = []
  var namePositions: [Name: Int] = [:]

  init<S: Sequence>(_ arguments: S) where S.Element == ArgumentDefinition {
    self.content = Array(arguments)
    self.namePositions = Dictionary(
      content.enumerated().flatMap { i, arg in arg.names.map { ($0.nameToMatch, i) } },
      uniquingKeysWith: { first, _ in first })
  }

  init() {}

  init(_ arg: ArgumentDefinition) {
    self.init([arg])
  }

  init(sets: [ArgumentSet]) {
    self.init(sets.joined())
  }

  mutating func append(_ arg: ArgumentDefinition) {
    let newPosition = content.count
    content.append(arg)
    for name in arg.names where namePositions[name.nameToMatch] == nil {
      namePositions[name.nameToMatch] = newPosition
    }
  }
}

extension ArgumentSet: CustomDebugStringConvertible {
  var debugDescription: String {
    content
      .map { $0.debugDescription }
      .joined(separator: " / ")
  }
}

extension ArgumentSet: RandomAccessCollection {
  var startIndex: Int { content.startIndex }
  var endIndex: Int { content.endIndex }
  subscript(position: Int) -> ArgumentDefinition {
    content[position]
  }
}

// MARK: Flag

extension ArgumentSet {
  /// Creates an argument set for a single Boolean flag.
  static func flag(key: InputKey, name: NameSpecification, default initialValue: Bool?, help: ArgumentHelp?) -> ArgumentSet {
    // The flag is required if initialValue is `nil`, otherwise it's optional
    let helpOptions: ArgumentDefinition.Help.Options = initialValue != nil ? .isOptional : []
    let defaultValueString = initialValue == true ? "true" : nil

    let help = ArgumentDefinition.Help(
      allValues: [],
      options: helpOptions,
      help: help,
      defaultValue: defaultValueString,
      key: key,
      isComposite: false)
    let arg = ArgumentDefinition(kind: .name(key: key, specification: name), help: help, completion: .default, update: .nullary({ (origin, name, values) in
      values.set(true, forKey: key, inputOrigin: origin)
    }), initial: { origin, values in
      if let initialValue = initialValue {
        values.set(initialValue, forKey: key, inputOrigin: origin)
      }
    })
    return ArgumentSet(arg)
  }

  static func updateFlag<Value: Equatable>(key: InputKey, value: Value, origin: InputOrigin, values: inout ParsedValues, hasUpdated: Bool, exclusivity: FlagExclusivity) throws -> Bool {
    switch (hasUpdated, exclusivity.base) {
    case (true, .exclusive):
      // This value has already been set.
      if let previous = values.element(forKey: key) {
        if (previous.value as? Value) == value {
          // setting the value again will consume the argument
          values.set(value, forKey: key, inputOrigin: origin)
        }
        else {
          throw ParserError.duplicateExclusiveValues(previous: previous.inputOrigin, duplicate: origin, originalInput: values.originalInput)
        }
      }
    case (true, .chooseFirst):
      values.update(forKey: key, inputOrigin: origin, initial: value, closure: { _ in })
    case (false, _), (_, .chooseLast):
      values.set(value, forKey: key, inputOrigin: origin)
    }
    return true
  }

  /// Creates an argument set for a pair of inverted Boolean flags.
  static func flag(
    key: InputKey,
    name: NameSpecification,
    default initialValue: Bool?,
    required: Bool,
    inversion: FlagInversion,
    exclusivity: FlagExclusivity,
    help: ArgumentHelp?) -> ArgumentSet
  {
    let helpOptions: ArgumentDefinition.Help.Options = required ? [] : .isOptional

    let (enableNames, disableNames) = inversion.enableDisableNamePair(for: key, name: name)
    let initialValueNames = initialValue.map {
      $0 ? enableNames : disableNames
    }

    let enableHelp = ArgumentDefinition.Help(allValues: [], options: helpOptions, help: help, defaultValue: initialValueNames?.first?.synopsisString, key: key, isComposite: true)
    let disableHelp = ArgumentDefinition.Help(allValues: [], options: [.isOptional], help: help, defaultValue: nil, key: key, isComposite: false)

    var hasUpdated = false
    let enableArg = ArgumentDefinition(kind: .named(enableNames), help: enableHelp, completion: .default, update: .nullary({ (origin, name, values) in
        hasUpdated = try ArgumentSet.updateFlag(key: key, value: true, origin: origin, values: &values, hasUpdated: hasUpdated, exclusivity: exclusivity)
    }), initial: { origin, values in
      if let initialValue = initialValue {
        values.set(initialValue, forKey: key, inputOrigin: origin)
      }
    })
    let disableArg = ArgumentDefinition(kind: .named(disableNames), help: disableHelp, completion: .default, update: .nullary({ (origin, name, values) in
        hasUpdated = try ArgumentSet.updateFlag(key: key, value: false, origin: origin, values: &values, hasUpdated: hasUpdated, exclusivity: exclusivity)
    }), initial: { _, _ in })
    return ArgumentSet([enableArg, disableArg])
  }

  /// Creates an argument set for an incrementing integer flag.
  static func counter(key: InputKey, name: NameSpecification, help: ArgumentHelp?) -> ArgumentSet {
    let help = ArgumentDefinition.Help(allValues: [], options: [.isOptional, .isRepeating], help: help, defaultValue: nil, key: key, isComposite: false)
    let arg = ArgumentDefinition(kind: .name(key: key, specification: name), help: help, completion: .default, update: .nullary({ (origin, name, values) in
      guard let a = values.element(forKey: key)?.value, let b = a as? Int else {
        throw ParserError.invalidState
      }
      values.set(b + 1, forKey: key, inputOrigin: origin)
    }), initial: { origin, values in
      values.set(0, forKey: key, inputOrigin: origin)
    })
    return ArgumentSet(arg)
  }
}

extension ArgumentSet {
  /// Fills the given `ParsedValues` instance with initial values from this
  /// argument set.
  func setInitialValues(into parsed: inout ParsedValues) throws {
    for arg in self {
      try arg.initial(InputOrigin(), &parsed)
    }
  }
}

extension ArgumentSet {
  /// Find an `ArgumentDefinition` that matches the given `ParsedArgument`.
  ///
  /// As we iterate over the values from the command line, we try to find a
  /// definition that matches the particular element.
  /// - Parameters:
  ///   - parsed: The argument from the command line
  ///   - origin: Where `parsed` came from.
  /// - Returns: The matching definition.
  func first(
    matching parsed: ParsedArgument
  ) -> ArgumentDefinition? {
    namePositions[parsed.name].map { content[$0] }
  }

  func firstPositional(
    named name: String
  ) -> ArgumentDefinition? {
    let key = InputKey(name: name, parent: nil)
    return first(where: { $0.help.keys.contains(key) })
  }
}

/// A parser for a given input and set of arguments defined by the given
/// command.
///
/// This parser will consume only the arguments that it understands. If any
/// arguments are declared to capture all remaining input, or a subcommand
/// is configured as such, parsing stops on the first positional argument or
/// unrecognized dash-prefixed argument.
struct LenientParser {
  var command: ParsableCommand.Type
  var argumentSet: ArgumentSet
  var inputArguments: SplitArguments

  init(_ command: ParsableCommand.Type, _ split: SplitArguments) {
    self.command = command
    self.argumentSet = ArgumentSet(command, visibility: .private, parent: nil)
    self.inputArguments = split
  }

  var defaultCapturesForPassthrough: Bool {
    command.defaultIncludesPassthroughArguments
  }

  var subcommands: [ParsableCommand.Type] {
    command.configuration.subcommands
  }

  mutating func parseValue(
    _ argument: ArgumentDefinition,
    _ parsed: ParsedArgument,
    _ originElement: InputOrigin.Element,
    _ update: ArgumentDefinition.Update.Unary,
    _ result: inout ParsedValues,
    _ usedOrigins: inout InputOrigin
  ) throws {
    let origin = InputOrigin(elements: [originElement])
    switch argument.parsingStrategy {
    case .default:
      // We need a value for this option.
      if let value = parsed.value {
        // This was `--foo=bar` style:
        try update(origin, parsed.name, value, &result)
        usedOrigins.formUnion(origin)
      } else if argument.allowsJoinedValue,
         let (origin2, value) = inputArguments.extractJoinedElement(at: originElement)
      {
        // Found a joined argument
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, String(value), &result)
        usedOrigins.formUnion(origins)
      } else if let (origin2, value) = inputArguments.popNextElementIfValue(after: originElement) {
        // Use `popNextElementIfValue(after:)` to handle cases where short option
        // labels are combined
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, value, &result)
        usedOrigins.formUnion(origins)
      } else {
        throw ParserError.missingValueForOption(origin, parsed.name)
      }

    case .scanningForValue:
      // We need a value for this option.
      if let value = parsed.value {
        // This was `--foo=bar` style:
        try update(origin, parsed.name, value, &result)
        usedOrigins.formUnion(origin)
      } else if argument.allowsJoinedValue,
          let (origin2, value) = inputArguments.extractJoinedElement(at: originElement) {
        // Found a joined argument
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, String(value), &result)
        usedOrigins.formUnion(origins)
      } else if let (origin2, value) = inputArguments.popNextValue(after: originElement) {
        // Use `popNext(after:)` to handle cases where short option
        // labels are combined
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, value, &result)
        usedOrigins.formUnion(origins)
      } else {
        throw ParserError.missingValueForOption(origin, parsed.name)
      }

    case .unconditional:
      // Use an attached value if it exists...
      if let value = parsed.value {
        // This was `--foo=bar` style:
        try update(origin, parsed.name, value, &result)
        usedOrigins.formUnion(origin)
      } else if argument.allowsJoinedValue,
          let (origin2, value) = inputArguments.extractJoinedElement(at: originElement) {
        // Found a joined argument
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, String(value), &result)
        usedOrigins.formUnion(origins)
      } else {
        guard let (origin2, value) = inputArguments.popNextElementAsValue(after: originElement) else {
          throw ParserError.missingValueForOption(origin, parsed.name)
        }
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, value, &result)
        usedOrigins.formUnion(origins)
      }

    case .allRemainingInput:
      // Reset initial value with the found input origins:
      try argument.initial(origin, &result)

      // Use an attached value if it exists...
      if let value = parsed.value {
        // This was `--foo=bar` style:
        try update(origin, parsed.name, value, &result)
        usedOrigins.formUnion(origin)
      } else if argument.allowsJoinedValue,
          let (origin2, value) = inputArguments.extractJoinedElement(at: originElement) {
        // Found a joined argument
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, String(value), &result)
        usedOrigins.formUnion(origins)
        inputArguments.removeAll(in: usedOrigins)
      }

      // ...and then consume the rest of the arguments
      while let (origin2, value) = inputArguments.popNextElementAsValue(after: originElement) {
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, value, &result)
        usedOrigins.formUnion(origins)
      }

    case .upToNextOption:
      // Use an attached value if it exists...
      if let value = parsed.value {
        // This was `--foo=bar` style:
        try update(origin, parsed.name, value, &result)
        usedOrigins.formUnion(origin)
      } else if argument.allowsJoinedValue,
          let (origin2, value) = inputArguments.extractJoinedElement(at: originElement) {
        // Found a joined argument
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, String(value), &result)
        usedOrigins.formUnion(origins)
        inputArguments.removeAll(in: usedOrigins)
      }

      // Clear out the initial origin first, since it can include
      // the exploded elements of an options group (see issue #327).
      usedOrigins.formUnion(origin)
      inputArguments.removeAll(in: origin)

      // Fix incorrect error message
      // for @Option array without values (see issue #434).
      guard let first = inputArguments.elements.first,
            first.isValue
      else {
        throw ParserError.missingValueForOption(origin, parsed.name)
      }

      // ...and then consume the arguments until hitting an option
      while let (origin2, value) = inputArguments.popNextElementIfValue() {
        let origins = origin.inserting(origin2)
        try update(origins, parsed.name, value, &result)
        usedOrigins.formUnion(origins)
      }

    case .postTerminator, .allUnrecognized:
      // These parsing kinds are for arguments only.
      throw ParserError.invalidState
    }
  }

  mutating func parsePositionalValues(
    from unusedInput: SplitArguments,
    into result: inout ParsedValues
  ) throws {
    var endOfInput = unusedInput.elements.endIndex

    // If this argument set includes a definition that should collect all the
    // post-terminator inputs, capture them before trying to fill other
    // `@Argument` definitions.
    if let postTerminatorArg = argumentSet.first(where: { def in
      def.isRepeatingPositional && def.parsingStrategy == .postTerminator
    }),
       case let .unary(update) = postTerminatorArg.update,
       let terminatorIndex = unusedInput.elements.firstIndex(where: \.isTerminator)
    {
      for input in unusedInput.elements[(terminatorIndex + 1)...] {
        // Everything post-terminator is a value, force-unwrapping here is safe:
        let value = input.value.valueString!
        try update([.argumentIndex(input.index)], nil, value, &result)
      }

      endOfInput = terminatorIndex
    }

    // Create a stack out of the remaining unused inputs that aren't "partial"
    // arguments (i.e. the individual components of a `-vix` grouped short
    // option input).
    var argumentStack = unusedInput.elements[..<endOfInput].filter {
      $0.index.subIndex == .complete
    }[...]
    guard !argumentStack.isEmpty else { return }

    /// Pops arguments off the stack until the next valid value. Skips over
    /// dash-prefixed inputs unless `unconditional` is `true`.
    func next(unconditional: Bool) -> SplitArguments.Element? {
      while let arg = argumentStack.popFirst() {
        if arg.isValue || unconditional {
          return arg
        }
      }

      return nil
    }

    // For all positional arguments, consume one or more inputs.
    var usedOrigins = InputOrigin()
    ArgumentLoop:
    for argumentDefinition in argumentSet {
      guard case .positional = argumentDefinition.kind else { continue }
      switch argumentDefinition.parsingStrategy {
      case .default, .allRemainingInput:
        break
      default:
        continue ArgumentLoop
      }
      guard case let .unary(update) = argumentDefinition.update else {
        preconditionFailure("Shouldn't see a nullary positional argument.")
      }
      let allowOptionsAsInput = argumentDefinition.parsingStrategy == .allRemainingInput

      repeat {
        guard let arg = next(unconditional: allowOptionsAsInput) else {
          break ArgumentLoop
        }
        let origin: InputOrigin.Element = .argumentIndex(arg.index)
        let value = unusedInput.originalInput(at: origin)!
        try update([origin], nil, value, &result)
        usedOrigins.insert(origin)
      } while argumentDefinition.isRepeatingPositional
    }

    // If there's an `.allUnrecognized` argument array, collect leftover args.
    if let allUnrecognizedArg = argumentSet.first(where: { def in
      def.isRepeatingPositional && def.parsingStrategy == .allUnrecognized
    }),
       case let .unary(update) = allUnrecognizedArg.update
    {
      result.capturedUnrecognizedArguments = SplitArguments(
        _elements: Array(argumentStack),
        originalInput: [])
      while let arg = argumentStack.popFirst() {
        let origin: InputOrigin.Element = .argumentIndex(arg.index)
        let value = unusedInput.originalInput(at: origin)!
        try update([origin], nil, value, &result)
      }
    }
  }

  mutating func parse() throws -> ParsedValues {
    let originalInput = inputArguments
    defer { inputArguments = originalInput }

    // If this argument set includes a positional argument that unconditionally
    // captures all remaining input, we use a different behavior, where we
    // shortcut out at the first sign of a positional argument or unrecognized
    // option/flag label.
    let capturesForPassthrough = defaultCapturesForPassthrough || argumentSet.contains(where: { arg in
      arg.isRepeatingPositional && arg.parsingStrategy == .allRemainingInput
    })

    var result = ParsedValues(elements: [:], originalInput: inputArguments.originalInput)
    var allUsedOrigins = InputOrigin()

    try argumentSet.setInitialValues(into: &result)

    // Loop over all arguments:
    ArgumentLoop:
    while let (origin, next) = inputArguments.popNext() {
      var usedOrigins = InputOrigin()
      defer {
        inputArguments.removeAll(in: usedOrigins)
        allUsedOrigins.formUnion(usedOrigins)
      }

      switch next.value {
      case .value(let argument):
        // Special handling for matching subcommand names. We generally want
        // parsing to skip over unrecognized input, but if the current
        // command or the matched subcommand captures all remaining input,
        // then we want to break out of parsing at this point.
        if let matchedSubcommand = subcommands.first(where: { $0._commandName == argument }) {
          if !matchedSubcommand.includesPassthroughArguments && defaultCapturesForPassthrough {
            continue ArgumentLoop
          } else if matchedSubcommand.includesPassthroughArguments {
            break ArgumentLoop
          }
        }

        // If we're capturing all, the first positional value represents the
        // start of positional input.
        if capturesForPassthrough { break ArgumentLoop }
        // We'll parse positional values later.
        break
      case let .option(parsed):
        // Look for an argument that matches this `--option` or `-o`-style
        // input. If we can't find one, just move on to the next input. We
        // defer catching leftover arguments until we've fully extracted all
        // the information for the selected command.
        guard let argument = argumentSet.first(matching: parsed) else
        {
          // If we're capturing all, an unrecognized option/flag is the start
          // of positional input. However, the first time we see an option
          // pack (like `-fi`) it looks like a long name with a single-dash
          // prefix, which may not match an argument even if its subcomponents
          // will match.
          if capturesForPassthrough && parsed.subarguments.isEmpty { break ArgumentLoop }

          // Otherwise, continue parsing. This option/flag may get picked up
          // by a child command.
          continue
        }

        switch argument.update {
        case let .nullary(update):
          // We don’t expect a value for this option.
          guard parsed.value == nil else {
            throw ParserError.unexpectedValueForOption(origin, parsed.name, parsed.value!)
          }
          try update([origin], parsed.name, &result)
          usedOrigins.insert(origin)
        case let .unary(update):
          try parseValue(argument, parsed, origin, update, &result, &usedOrigins)
        }
      case .terminator:
        // Ignore the terminator, it might get picked up as a positional value later.
        break
      }
    }

    // We have parsed all non-positional values at this point.
    // Next: parse / consume the positional values.
    var unusedArguments = originalInput
    unusedArguments.removeAll(in: allUsedOrigins)
    try parsePositionalValues(from: unusedArguments, into: &result)

    return result
  }
}

struct CommandError: Error {
  var commandStack: [ParsableCommand.Type]
  var parserError: ParserError
}

struct HelpRequested: Error {
  var visibility: ArgumentVisibility
}

struct CommandParser {
  let commandTree: Tree<ParsableCommand.Type>
  var currentNode: Tree<ParsableCommand.Type>
  var decodedArguments: [DecodedArguments] = []

  var rootCommand: ParsableCommand.Type {
    commandTree.element
  }

  var commandStack: [ParsableCommand.Type] {
    let result = decodedArguments.compactMap { $0.commandType }
    if currentNode.element == result.last {
      return result
    } else {
      return result + [currentNode.element]
    }
  }

  init(_ rootCommand: ParsableCommand.Type) {
    do {
      self.commandTree = try Tree(root: rootCommand)
    } catch Tree<ParsableCommand.Type>.InitializationError.recursiveSubcommand(let command) {
      fatalError("The ParsableCommand \"\(command)\" can't have itself as its own subcommand.")
    } catch {
      fatalError("Unexpected error: \(error).")
    }
    self.currentNode = commandTree

    // A command tree that has a depth greater than zero gets a `help`
    // subcommand.
    if !commandTree.isLeaf {
      commandTree.addChild(Tree(HelpCommand.self))
    }
  }
}

extension CommandParser {
  /// Consumes the next argument in `split` if it matches a subcommand at the
  /// current node of the command tree.
  ///
  /// If a matching subcommand is found, the subcommand argument is consumed
  /// in `split`.
  ///
  /// - Returns: A node for the matched subcommand if one was found;
  ///   otherwise, `nil`.
  fileprivate func consumeNextCommand(split: inout SplitArguments) -> Tree<ParsableCommand.Type>? {
    guard let (origin, element) = split.peekNext(),
      element.isValue,
      let value = split.originalInput(at: origin),
      let subcommandNode = currentNode.firstChild(withName: value)
    else { return nil }
    _ = split.popNextValue()
    return subcommandNode
  }

  /// Throws a `HelpRequested` error if the user has specified any of the
  /// built-in flags.
  ///
  /// - Parameters:
  ///   - split: The remaining arguments to examine.
  ///   - requireSoloArgument: `true` if the built-in flag must be the only
  ///     one remaining for this to catch it.
  func checkForBuiltInFlags(
    _ split: SplitArguments,
    requireSoloArgument: Bool = false
  ) throws {
    guard !requireSoloArgument || split.count == 1 else { return }

    // Look for help flags
    guard !split.contains(anyOf: self.commandStack.getHelpNames(visibility: .default)) else {
      throw HelpRequested(visibility: .default)
    }

    // Look for help-hidden flags
    guard !split.contains(anyOf: self.commandStack.getHelpNames(visibility: .hidden)) else {
      throw HelpRequested(visibility: .hidden)
    }

    // Look for a version flag if any commands in the stack define a version
    if commandStack.contains(where: { !$0.configuration.version.isEmpty }) {
      guard !split.contains(Name.long("version")) else {
        throw CommandError(commandStack: commandStack, parserError: .versionRequested)
      }
    }
  }

  /// Returns the last parsed value if there are no remaining unused arguments.
  ///
  /// If there are remaining arguments or if no commands have been parsed,
  /// this throws an error.
  fileprivate func extractLastParsedValue(_ split: SplitArguments) throws -> ParsableCommand {
    try checkForBuiltInFlags(split)

    // We should have used up all arguments at this point:
    guard !split.containsNonTerminatorArguments else {
      // Check if one of the arguments is an unknown option
      for element in split.elements {
        if case .option(let argument) = element.value {
          throw ParserError.unknownOption(InputOrigin.Element.argumentIndex(element.index), argument.name)
        }
      }

      let extra = split.coalescedExtraElements()
      throw ParserError.unexpectedExtraValues(extra)
    }

    guard let lastCommand = decodedArguments.lazy.compactMap({ $0.command }).last else {
      throw ParserError.invalidState
    }

    return lastCommand
  }

  /// Extracts the current command from `split`, throwing if decoding isn't
  /// possible.
  fileprivate mutating func parseCurrent(_ split: inout SplitArguments) throws -> ParsableCommand {
    // Parse the arguments, ignoring anything unexpected
    var parser = LenientParser(currentNode.element, split)
    let values = try parser.parse()

    if currentNode.element.includesAllUnrecognizedArgument {
      // If this command includes an all-unrecognized argument, any built-in
      // flags will have been parsed into that argument. Check for flags
      // before decoding.
      try checkForBuiltInFlags(values.capturedUnrecognizedArguments)
    }

    // Decode the values from ParsedValues into the ParsableCommand:
    let decoder = ArgumentDecoder(values: values, previouslyDecoded: decodedArguments)
    var decodedResult: ParsableCommand
    do {
      decodedResult = try currentNode.element.init(from: decoder)
    } catch let error {
      // If decoding this command failed, see if they were asking for
      // help before propagating that parsing failure.
      try checkForBuiltInFlags(split)
      throw error
    }

    // Decoding was successful, so remove the arguments that were used
    // by the decoder.
    split.removeAll(in: decoder.usedOrigins)

    // Save the decoded results to add to the next command.
    let newDecodedValues = decoder.previouslyDecoded
      .filter { prev in !decodedArguments.contains(where: { $0.type == prev.type })}
    decodedArguments.append(contentsOf: newDecodedValues)
    decodedArguments.append(DecodedArguments(type: currentNode.element, value: decodedResult))

    return decodedResult
  }

  /// Starting with the current node, extracts commands out of `split` and
  /// descends into subcommands as far as possible.
  internal mutating func descendingParse(_ split: inout SplitArguments) throws {
    while true {
      var parsedCommand = try parseCurrent(&split)

      // after decoding a command, make sure to validate it
      do {
        try parsedCommand.validate()
        var lastArgument = decodedArguments.removeLast()
        lastArgument.value = parsedCommand
        decodedArguments.append(lastArgument)
      } catch {
        try checkForBuiltInFlags(split)
        throw CommandError(commandStack: commandStack, parserError: ParserError.userValidationError(error))
      }

      // Look for next command in the argument list.
      if let nextCommand = consumeNextCommand(split: &split) {
        currentNode = nextCommand
        continue
      }

      // Look for the help flag before falling back to a default command.
      try checkForBuiltInFlags(split, requireSoloArgument: true)

      // No command was found, so fall back to the default subcommand.
      if let defaultSubcommand = currentNode.element.configuration.defaultSubcommand {
        guard let subcommandNode = currentNode.firstChild(equalTo: defaultSubcommand) else {
          throw ParserError.invalidState
        }
        currentNode = subcommandNode
        continue
      }

      // No more subcommands to parse.
      return
    }
  }

  /// Returns the fully-parsed matching command for `arguments`, or an
  /// appropriate error.
  ///
  /// - Parameter arguments: The array of arguments to parse. This should not
  ///   include the command name as the first argument.
  mutating func parse(arguments: [String]) -> Result<ParsableCommand, CommandError> {
    var split: SplitArguments
    do {
      split = try SplitArguments(arguments: arguments)
    } catch let error as ParserError {
      return .failure(CommandError(commandStack: [commandTree.element], parserError: error))
    } catch {
      return .failure(CommandError(commandStack: [commandTree.element], parserError: .invalidState))
    }

    do {
      try descendingParse(&split)
      let result = try extractLastParsedValue(split)

      // HelpCommand is a valid result, but needs extra information about
      // the tree from the parser to build its stack of commands.
      if var helpResult = result as? HelpCommand {
        try helpResult.buildCommandStack(with: self)
        return .success(helpResult)
      }
      return .success(result)
    } catch let error as CommandError {
      return .failure(error)
    } catch let error as ParserError {
      let error = arguments.isEmpty ? ParserError.noArguments(error) : error
      return .failure(CommandError(commandStack: commandStack, parserError: error))
    } catch let helpRequest as HelpRequested {
      return .success(HelpCommand(
        commandStack: commandStack,
        visibility: helpRequest.visibility))
    } catch {
      return .failure(CommandError(commandStack: commandStack, parserError: .invalidState))
    }
  }
}

extension CommandParser {



}

// MARK: Building Command Stacks

extension CommandParser {
  /// Builds an array of commands that matches the given command names.
  ///
  /// This stops building the stack if it encounters any command names that
  /// aren't in the command tree, so it's okay to pass a list of arbitrary
  /// commands. Will always return at least the root of the command tree.
  func commandStack(for commandNames: [String]) -> [ParsableCommand.Type] {
    var node = commandTree
    var result = [node.element]

    for name in commandNames {
      guard let nextNode = node.firstChild(withName: name) else {
        // Reached a non-command argument.
        // Ignore anything after this point
        return result
      }
      result.append(nextNode.element)
      node = nextNode
    }

    return result
  }

  func commandStack(for subcommand: ParsableCommand.Type) -> [ParsableCommand.Type] {
    let path = commandTree.path(to: subcommand)
    return path.isEmpty
      ? [commandTree.element]
      : path
  }
}

extension SplitArguments {
  func contains(_ needle: Name) -> Bool {
    self.elements.contains {
      switch $0.value {
      case .option(.name(let name)),
           .option(.nameWithValue(let name, _)):
        return name == needle
      default:
        return false
      }
    }
  }

  func contains(anyOf names: [Name]) -> Bool {
    self.elements.contains {
      switch $0.value {
      case .option(.name(let name)),
           .option(.nameWithValue(let name, _)):
        return names.contains(name)
      default:
        return false
      }
    }
  }
}

/// Represents the path to a parsed field, annotated with ``Flag``, ``Option``
/// or ``Argument``. Fields that are directly declared on a ``ParsableComand``
/// have a path of length 1, while fields that are declared indirectly (and
/// included via an option group) have longer paths.
struct InputKey: Hashable {
  /// The name of the input key.
  var name: String

  /// The path through the field's parents, if any.
  var path: [String]

  /// The full path of the field.
  var fullPath: [String] { path + [name] }

  /// Constructs a new input key, cleaning the name, with the specified parent.
  ///
  /// - Parameter name: The name of the key.
  /// - Parameter parent: The input key of the parent.
  init(name: String, parent: InputKey?) {
    // Property wrappers have underscore-prefixed names, so we remove the
    // leading `_`, if present.
    self.name = name.first == "_"
      ? String(name.dropFirst(1))
      : name
    self.path = parent?.fullPath ?? []
  }

  /// Constructs a new input key from the given coding key and parent path.
  ///
  /// - Parameter codingKey: The base ``CodingKey``. Leading underscores in
  ///   `codingKey` is preserved.
  /// - Parameter path: The list of ``CodingKey`` values that lead to this one.
  ///   `path` may be empty.
  @inlinable
  init(codingKey: CodingKey, path: [CodingKey]) {
    self.name = codingKey.stringValue
    self.path = path.map { $0.stringValue }
  }
}

extension InputKey: CustomStringConvertible {
  var description: String {
    fullPath.joined(separator: ".")
  }
}

/// Specifies where a given input came from.
///
/// When reading from the command line, a value might originate from a single
/// index, multiple indices, or from part of an index. For this command:
///
///     struct Example: ParsableCommand {
///         @Flag(name: .short) var verbose = false
///         @Flag(name: .short) var expert = false
///
///         @Option var count: Int
///     }
///
/// ...with this usage:
///
///     $ example -ve --count 5
///
/// The parsed value for the `count` property will come from indices `1` and
/// `2`, while the value for `verbose` will come from index `1`, sub-index `0`.
struct InputOrigin: Equatable, ExpressibleByArrayLiteral {
  enum Element: Comparable, Hashable {
    /// The input value came from a property's default value, not from a
    /// command line argument.
    case defaultValue

    /// The input value came from the specified index in the argument string.
    case argumentIndex(SplitArguments.Index)

    var baseIndex: Int? {
      switch self {
      case .defaultValue:
        return nil
      case .argumentIndex(let i):
        return i.inputIndex.rawValue
      }
    }

    var subIndex: Int? {
      switch self {
      case .defaultValue:
        return nil
      case .argumentIndex(let i):
        switch i.subIndex {
        case .complete: return nil
        case .sub(let n): return n
        }
      }
    }
  }

  private var _elements: Set<Element> = []
  var elements: [Element] {
    Array(_elements).sorted()
  }

  init() {
  }

  init(elements: [Element]) {
    _elements = Set(elements)
  }

  init(element: Element) {
    _elements = Set([element])
  }

  init(arrayLiteral elements: Element...) {
    self.init(elements: elements)
  }

  init(argumentIndex: SplitArguments.Index) {
    self.init(element: .argumentIndex(argumentIndex))
  }

  mutating func insert(_ other: Element) {
    guard !_elements.contains(other) else { return }
    _elements.insert(other)
  }

  func inserting(_ other: Element) -> Self {
    guard !_elements.contains(other) else { return self }
    var result = self
    result.insert(other)
    return result
  }

  mutating func formUnion(_ other: InputOrigin) {
    _elements.formUnion(other._elements)
  }

  func forEach(_ closure: (Element) -> Void) {
    _elements.forEach(closure)
  }
}

extension InputOrigin {
  var isDefaultValue: Bool {
    return _elements.count == 1 && _elements.first == .defaultValue
  }
}

extension InputOrigin.Element {
  static func < (lhs: Self, rhs: Self) -> Bool {
    switch (lhs, rhs) {
    case (.argumentIndex(let l), .argumentIndex(let r)):
      return l < r
    case (.argumentIndex, .defaultValue):
      return true
    case (.defaultValue, _):
      return false
    }
  }
}

enum Name {
  /// A name (usually multi-character) prefixed with `--` (2 dashes) or equivalent.
  case long(String)
  /// A single character name prefixed with `-` (1 dash) or equivalent.
  ///
  /// Usually supports mixing multiple short names with a single dash, i.e. `-ab` is equivalent to `-a -b`.
  case short(Character, allowingJoined: Bool = false)
  /// A name (usually multi-character) prefixed with `-` (1 dash).
  case longWithSingleDash(String)
}

extension Name {
  init(_ baseName: Substring) {
    assert(baseName.first == "-", "Attempted to create name for unprefixed argument")
    if baseName.hasPrefix("--") {
      self = .long(String(baseName.dropFirst(2)))
    } else if baseName.count == 2 { // single character "-x" style
      self = .short(baseName.last!)
    } else { // long name with single dash
      self = .longWithSingleDash(String(baseName.dropFirst()))
    }
  }
}

// short argument names based on the synopsisString
// this will put the single - options before the -- options
extension Name: Comparable {
  static func < (lhs: Name, rhs: Name) -> Bool {
    return lhs.synopsisString < rhs.synopsisString
  }
}

extension Name: Hashable { }

extension Name {
  enum Case: Equatable {
    case long
    case short
    case longWithSingleDash
  }

  var `case`: Case {
    switch self {
    case .short:
      return .short
    case .longWithSingleDash:
      return .longWithSingleDash
    case .long:
      return .long
    }
  }
}

extension Name {
  var synopsisString: String {
    switch self {
    case .long(let n):
      return "--\(n)"
    case .short(let n, _):
      return "-\(n)"
    case .longWithSingleDash(let n):
      return "-\(n)"
    }
  }

  var valueString: String {
    switch self {
    case .long(let n):
      return n
    case .short(let n, _):
      return String(n)
    case .longWithSingleDash(let n):
      return n
    }
  }

  var allowsJoined: Bool {
    switch self {
    case .short(_, let allowingJoined):
      return allowingJoined
    default:
      return false
    }
  }

  /// The instance to match against user input -- this always has
  /// `allowingJoined` as `false`, since that's the way input is parsed.
  var nameToMatch: Name {
    switch self {
    case .long, .longWithSingleDash: return self
    case .short(let c, _): return .short(c)
    }
  }
}

extension BidirectionalCollection where Element == Name {
  var preferredName: Name? {
    first { $0.case != .short } ?? first
  }

  var partitioned: [Name] {
    filter { $0.case == .short } + filter { $0.case != .short }
  }
}

enum Parsed<Value> {
  /// The definition of how this value is to be parsed from command-line arguments.
  ///
  /// Internally, this wraps an `ArgumentSet`, but that’s not `public` since it’s
  /// an implementation detail.
  case value(Value)
  case definition((InputKey) -> ArgumentSet)

  internal init(_ makeSet: @escaping (InputKey) -> ArgumentSet) {
    self = .definition(makeSet)
  }
}

/// A type that wraps a `Parsed` instance to act as a property wrapper.
///
/// This protocol simplifies the implementations of property wrappers that
/// wrap the `Parsed` type.
internal protocol ParsedWrapper: Decodable, ArgumentSetProvider {
  associatedtype Value
  var _parsedValue: Parsed<Value> { get }
  init(_parsedValue: Parsed<Value>)
}

/// A `Parsed`-wrapper whose value type knows how to decode itself. Types that
/// conform to this protocol can initialize their values directly from a
/// `Decoder`.
internal protocol DecodableParsedWrapper: ParsedWrapper
  where Value: Decodable
{
  init(_parsedValue: Parsed<Value>)
}

extension ParsedWrapper {
  init(_decoder: Decoder) throws {
    guard let d = _decoder as? SingleValueDecoder else {
      throw ParserError.invalidState
    }
    guard let value = d.parsedElement?.value as? Value else {
      throw ParserError.noValue(forKey: d.parsedElement?.key ?? d.key)
    }

    self.init(_parsedValue: .value(value))
  }

  func argumentSet(for key: InputKey) -> ArgumentSet {
    switch _parsedValue {
    case .value:
      fatalError("Trying to get the argument set from a resolved/parsed property.")
    case .definition(let a):
      return a(key)
    }
  }
}

extension ParsedWrapper where Value: Decodable {
  init(_decoder: Decoder) throws {
    var value: Value

    do {
      value = try Value.init(from: _decoder)
    } catch {
      if let d = _decoder as? SingleValueDecoder,
        let v = d.parsedElement?.value as? Value {
        value = v
      } else {
        throw error
      }
    }

    self.init(_parsedValue: .value(value))
  }
}

/// The resulting values after parsing the command-line arguments.
///
/// This is a flat key-value list of values.
struct ParsedValues {
  struct Element {
    var key: InputKey
    var value: Any?
    /// Where in the input that this came from.
    var inputOrigin: InputOrigin
    fileprivate var shouldClearArrayIfParsed = true
  }

  /// These are the parsed key-value pairs.
  var elements: [InputKey: Element] = [:]

  /// This is the *original* array of arguments that this was parsed from.
  ///
  /// This is used for error output generation.
  var originalInput: [String]

  /// Any arguments that are captured into an `.allUnrecognized` argument.
  var capturedUnrecognizedArguments = SplitArguments(originalInput: [])
}

extension ParsedValues {
  mutating func set(_ new: Any?, forKey key: InputKey, inputOrigin: InputOrigin) {
    set(Element(key: key, value: new, inputOrigin: inputOrigin))
  }

  mutating func set(_ element: Element) {
    if let e = elements[element.key] {
      // Merge the source values. We need to keep track
      // of any previous source indexes we have used for
      // this key.
      var element = element
      element.inputOrigin.formUnion(e.inputOrigin)
      elements[element.key] = element
    } else {
      elements[element.key] = element
    }
  }

  func element(forKey key: InputKey) -> Element? {
    elements[key]
  }

  mutating func update<A>(forKey key: InputKey, inputOrigin: InputOrigin, initial: A, closure: (inout A) -> Void) {
    var e = element(forKey: key) ?? Element(key: key, value: initial, inputOrigin: InputOrigin())
    var v = (e.value as? A ) ?? initial
    closure(&v)
    e.value = v
    e.inputOrigin.formUnion(inputOrigin)
    set(e)
  }

  mutating func update<A>(forKey key: InputKey, inputOrigin: InputOrigin, initial: [A], closure: (inout [A]) -> Void) {
    var e = element(forKey: key) ?? Element(key: key, value: initial, inputOrigin: InputOrigin())
    var v = (e.value as? [A] ) ?? initial
    // The first time a value is parsed from command line, empty array of any default values.
    if e.shouldClearArrayIfParsed {
      v.removeAll()
      e.shouldClearArrayIfParsed = false
    }
    closure(&v)
    e.value = v
    e.inputOrigin.formUnion(inputOrigin)
    set(e)
  }
}

/// Gets thrown while parsing and will be handled by the error output generation.
enum ParserError: Error {
  case helpRequested(visibility: ArgumentVisibility)
  case versionRequested

  case notImplemented
  case invalidState
  case unknownOption(InputOrigin.Element, Name)
  case invalidOption(String)
  case nonAlphanumericShortOption(Character)
  /// The option was there, but its value is missing, e.g. `--name` but no value for the `name`.
  case missingValueForOption(InputOrigin, Name)
  case unexpectedValueForOption(InputOrigin.Element, Name, String)
  case unexpectedExtraValues([(InputOrigin, String)])
  case duplicateExclusiveValues(previous: InputOrigin, duplicate: InputOrigin, originalInput: [String])
  /// We need a value for the given key, but it’s not there. Some non-optional option or argument is missing.
  case noValue(forKey: InputKey)
  case unableToParseValue(InputOrigin, Name?, String, forKey: InputKey, originalError: Error?)
  case missingSubcommand
  case userValidationError(Error)
  case noArguments(Error)
}

/// These are errors used internally to the parsing, and will not be exposed to the help generation.
enum InternalParseError: Error {
  case wrongType(Any?, forKey: InputKey)
  case subcommandNameMismatch
  case subcommandLevelMismatch(Int, Int)
  case subcommandLevelMissing(Int)
  case subcommandLevelDuplicated(Int)
  case expectedCommandButNoneFound
}

/// A single `-f`, `--foo`, or `--foo=bar`.
///
/// When parsing, we might see `"--foo"` or `"--foo=bar"`.
enum ParsedArgument: Equatable, CustomStringConvertible {
  /// `--foo` or `-f`
  case name(Name)
  /// `--foo=bar`
  case nameWithValue(Name, String)

  init<S: StringProtocol>(_ str: S) where S.SubSequence == Substring {
    let indexOfEqualSign = str.firstIndex(of: "=") ?? str.endIndex
    let (baseName, value) = (str[..<indexOfEqualSign], str[indexOfEqualSign...].dropFirst())
    let name = Name(baseName)
    self = value.isEmpty
      ? .name(name)
      : .nameWithValue(name, String(value))
  }

  /// An array of short arguments and their indices in the original base
  /// name, if this argument could be a combined pack of short arguments.
  ///
  /// For `subarguments` to be non-empty:
  ///
  /// 1) This must have a single-dash prefix (not `--foo`)
  /// 2) This must not have an attached value (not `-foo=bar`)
  var subarguments: [(Int, ParsedArgument)] {
    switch self {
    case .nameWithValue: return []
    case .name(let name):
      switch name {
      case .longWithSingleDash(let base):
        return base.enumerated().map {
          ($0, .name(.short($1)))
        }
      case .long, .short:
        return []
      }
    }
  }

  var name: Name {
    switch self {
    case let .name(n): return n
    case let .nameWithValue(n, _): return n
    }
  }

  var value: String? {
    switch self {
    case .name: return nil
    case let .nameWithValue(_, v): return v
    }
  }

  var description: String {
    switch self {
    case .name(let name):
      return name.synopsisString
    case .nameWithValue(let name, let value):
      return "\(name.synopsisString)=\(value)"
    }
  }
}

/// A collection of parsed command-line arguments.
///
/// This is a flat list of *values* and *options*. E.g. the
/// arguments `["--foo", "bar"]` would be parsed into
/// `[.option(.name(.long("foo"))), .value("bar")]`.
struct SplitArguments {
  struct Element: Equatable {
    enum Value: Equatable {
      case option(ParsedArgument)
      case value(String)
      /// The `--` marker
      case terminator

      var valueString: String? {
        switch self {
        case .value(let str):
          return str
        case .option, .terminator:
          return nil
        }
      }
    }

    var value: Value
    var index: Index

    static func option(_ arg: ParsedArgument, index: Index) -> Element {
      Element(value: .option(arg), index: index)
    }

    static func value(_ str: String, index: Index) -> Element {
      Element(value: .value(str), index: index)
    }

    static func terminator(index: Index) -> Element {
      Element(value: .terminator, index: index)
    }
  }

  /// The position of the original input string for an element.
  ///
  /// For example, if `originalInput` is `["--foo", "-vh"]`, there are index
  /// positions 0 (`--foo`) and 1 (`-vh`).
  struct InputIndex: RawRepresentable, Hashable, Comparable {
    var rawValue: Int

    static func <(lhs: InputIndex, rhs: InputIndex) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }

  /// The position within an option for an element.
  ///
  /// Single-dash prefixed options can be treated as a whole option or as a
  /// group of individual short options. For example, the input `-vh` is split
  /// into three elements, with distinct sub-indexes:
  ///
  /// - `-vh`: `.complete`
  /// - `-v`: `.sub(0)`
  /// - `-h`: `.sub(1)`
  enum SubIndex: Hashable, Comparable {
    case complete
    case sub(Int)

    static func <(lhs: SubIndex, rhs: SubIndex) -> Bool {
      switch (lhs, rhs) {
      case (.complete, .sub):
        return true
      case (.sub(let l), .sub(let r)) where l < r:
        return true
      default:
        return false
      }
    }
  }

  /// An index into the original input and the sub-index of an element.
  struct Index: Hashable, Comparable {
    static func < (lhs: SplitArguments.Index, rhs: SplitArguments.Index) -> Bool {
      if lhs.inputIndex < rhs.inputIndex {
        return true
      } else if lhs.inputIndex == rhs.inputIndex {
        return lhs.subIndex < rhs.subIndex
      } else {
        return false
      }
    }

    var inputIndex: InputIndex
    var subIndex: SubIndex = .complete

    var completeIndex: Index {
      return Index(inputIndex: inputIndex)
    }
  }

  /// The parsed arguments.
  var _elements: [Element] = []
  var firstUnused: Int = 0

  /// The original array of arguments that was used to generate this instance.
  var originalInput: [String]

  /// The unused arguments represented by this instance.
  var elements: ArraySlice<Element> {
    _elements[firstUnused...]
  }

  var count: Int {
    elements.count
  }
}

extension SplitArguments: Equatable {}

extension SplitArguments.Element: CustomDebugStringConvertible {
  var debugDescription: String {
    switch value {
    case .option(.name(let name)):
      return name.synopsisString
    case .option(.nameWithValue(let name, let value)):
      return name.synopsisString + "; value '\(value)'"
    case .value(let value):
      return "value '\(value)'"
    case .terminator:
      return "terminator"
    }
  }
}

extension SplitArguments.Index: CustomStringConvertible {
  var description: String {
    switch subIndex {
    case .complete: return "\(inputIndex.rawValue)"
    case .sub(let sub): return "\(inputIndex.rawValue).\(sub)"
    }
  }
}

extension SplitArguments: CustomStringConvertible {
  var description: String {
    guard !isEmpty else { return "<empty>" }
    return elements
      .map { element -> String in
        switch element.value {
        case .option(.name(let name)):
          return "[\(element.index)] \(name.synopsisString)"
        case .option(.nameWithValue(let name, let value)):
          return "[\(element.index)] \(name.synopsisString)='\(value)'"
        case .value(let value):
          return "[\(element.index)] '\(value)'"
        case .terminator:
          return "[\(element.index)] --"
        }
    }
    .joined(separator: " ")
  }
}

extension SplitArguments.Element {
  var isValue: Bool {
    switch value {
    case .value: return true
    case .option, .terminator: return false
    }
  }

  var isTerminator: Bool {
    switch value {
    case .terminator: return true
    case .option, .value: return false
    }
  }
}

extension SplitArguments {
  /// `true` if the arguments are empty.
  var isEmpty: Bool {
    elements.isEmpty
  }

  /// `false` if the arguments are empty, or if the only remaining argument is
  /// the `--` terminator.
  var containsNonTerminatorArguments: Bool {
    if elements.isEmpty { return false }
    if elements.count > 1 { return true }

    if elements.first?.isTerminator == true { return false }
    else { return true }
  }

  /// Returns the original input string at the given origin, or `nil` if
  /// `origin` is a sub-index.
  func originalInput(at origin: InputOrigin.Element) -> String? {
    guard case let .argumentIndex(index) = origin else {
      return nil
    }
    return originalInput[index.inputIndex.rawValue]
  }

  /// Returns the position in `elements` of the given input origin.
  func position(of origin: InputOrigin.Element) -> Int? {
    guard case let .argumentIndex(index) = origin else { return nil }
    return elements.firstIndex(where: { $0.index == index })
  }

  /// Returns the position in `elements` of the first element after the given
  /// input origin.
  func position(after origin: InputOrigin.Element) -> Int? {
    guard case let .argumentIndex(index) = origin else { return nil }
    return elements.firstIndex(where: { $0.index > index })
  }

  mutating func popNext() -> (InputOrigin.Element, Element)? {
    guard let element = elements.first else { return nil }
    removeFirst()
    return (.argumentIndex(element.index), element)
  }

  func peekNext() -> (InputOrigin.Element, Element)? {
    guard let element = elements.first else { return nil }
    return (.argumentIndex(element.index), element)
  }

  func extractJoinedElement(at origin: InputOrigin.Element) -> (InputOrigin.Element, String)? {
    guard case let .argumentIndex(index) = origin else { return nil }

    // Joined arguments only apply when parsing the first sub-element of a
    // larger input argument.
    guard index.subIndex == .sub(0) else { return nil }

    // Rebuild the origin position for the full argument string, e.g. `-Ddebug`
    // instead of just the `-D` portion.
    let completeOrigin = InputOrigin.Element.argumentIndex(index.completeIndex)

    // Get the value from the original string, following the dash and short
    // option name. For example, for `-Ddebug`, drop the `-D`, leaving `debug`
    // as the value.
    let value = String(originalInput(at: completeOrigin)!.dropFirst(2))

    return (completeOrigin, value)
  }

  /// Pops the element immediately after the given index, if it is a `.value`.
  ///
  /// This is used to get the next value in `-fb name` where `name` is the
  /// value for `-f`, or `--foo name` where `name` is the value for `--foo`.
  /// If `--foo` expects a value, an input of `--foo --bar name` will return
  /// `nil`, since the option `--bar` comes before the value `name`.
  mutating func popNextElementIfValue(after origin: InputOrigin.Element) -> (InputOrigin.Element, String)? {
    // Look for the index of the input that comes from immediately after
    // `origin` in the input string. We look at the input index so that
    // packed short options can be followed, in order, by their values.
    // e.g. "-fn f-value n-value"
    guard let start = position(after: origin),
      let elementIndex = elements[start...].firstIndex(where: { $0.index.subIndex == .complete })
      else { return nil }

    // Only succeed if the element is a value (not prefixed with a dash)
    guard case .value(let value) = elements[elementIndex].value
      else { return nil }

    defer { remove(at: elementIndex) }
    let matchedArgumentIndex = elements[elementIndex].index
    return (.argumentIndex(matchedArgumentIndex), value)
  }

  /// Pops the next `.value` after the given index.
  ///
  /// This is used to get the next value in `-f -b name` where `name` is the value of `-f`.
  mutating func popNextValue(after origin: InputOrigin.Element) -> (InputOrigin.Element, String)? {
    guard let start = position(after: origin) else { return nil }
    guard let resultIndex = elements[start...].firstIndex(where: { $0.isValue }) else { return nil }

    defer { remove(at: resultIndex) }
    return (.argumentIndex(elements[resultIndex].index), elements[resultIndex].value.valueString!)
  }

  /// Pops the element after the given index as a value.
  ///
  /// This will re-interpret `.option` and `.terminator` as values, i.e.
  /// read from the `originalInput`.
  ///
  /// For an input such as `--a --b foo`, if passed the origin of `--a`,
  /// this will first pop the value `--b`, then the value `foo`.
  mutating func popNextElementAsValue(after origin: InputOrigin.Element) -> (InputOrigin.Element, String)? {
    guard let start = position(after: origin) else { return nil }
    // Elements are sorted by their `InputIndex`. Find the first `InputIndex`
    // after `origin`:
    guard let nextIndex = elements[start...].first(where: { $0.index.subIndex == .complete })?.index else { return nil }
    // Remove all elements with this `InputIndex`:
    remove(at: nextIndex)
    // Return the original input
    return (.argumentIndex(nextIndex), originalInput[nextIndex.inputIndex.rawValue])
  }

  /// Pops the next element if it is a value.
  ///
  /// If the current elements are `--b foo`, this will return `nil`. If the
  /// elements are `foo --b`, this will return the value `foo`.
  mutating func popNextElementIfValue() -> (InputOrigin.Element, String)? {
    guard let element = elements.first, element.isValue else { return nil }
    removeFirst()
    return (.argumentIndex(element.index), element.value.valueString!)
  }

  /// Finds and "pops" the next element that is a value.
  ///
  /// If the current elements are `--a --b foo`, this will remove and return
  /// `foo`.
  mutating func popNextValue() -> (Index, String)? {
    guard let idx = elements.firstIndex(where: { $0.isValue })
      else { return nil }
    let e = elements[idx]
    remove(at: idx)
    return (e.index, e.value.valueString!)
  }

  /// Finds and returns the next element that is a value.
  func peekNextValue() -> (Index, String)? {
    guard let idx = elements.firstIndex(where: { $0.isValue })
      else { return nil }
    let e = elements[idx]
    return (e.index, e.value.valueString!)
  }

  /// Removes the first element in `elements`.
  mutating func removeFirst() {
    firstUnused += 1
  }

  /// Removes the element at the given position.
  mutating func remove(at position: Int) {
    guard position >= firstUnused else {
      return
    }

    // This leaves duplicates of still to-be-used arguments in the unused
    // portion of the _elements array.
    for i in (firstUnused..<position).reversed() {
      _elements[i + 1] = _elements[i]
    }
    firstUnused += 1
  }

  /// Removes the elements in the given subrange.
  mutating func remove(subrange: Range<Int>) {
    var lo = subrange.startIndex
    var hi = subrange.endIndex

    // This leaves duplicates of still to-be-used arguments in the unused
    // portion of the _elements array.
    while lo > firstUnused {
      hi -= 1
      lo -= 1
      _elements[hi] = _elements[lo]
    }
    firstUnused += subrange.count
  }

  /// Removes the element(s) at the given `Index`.
  ///
  /// - Note: This may remove multiple elements.
  ///
  /// For combined _short_ arguments such as `-ab`, these will gets parsed into
  /// 3 elements: The _long with short dash_ `ab`, and 2 _short_ `a` and `b`. All of these
  /// will have the same `inputIndex` but different `subIndex`. When either of the short ones
  /// is removed, that will remove the _long with short dash_ as well. Likewise, if the
  /// _long with short dash_ is removed, that will remove both of the _short_ elements.
  mutating func remove(at position: Index) {
    guard !isEmpty else { return }

    // Find the first element at the given input index. Since `elements` is
    // always sorted by input index, we can leave this method if we see a
    // higher value than `position`.
    var start = elements.startIndex
    while start < elements.endIndex {
      if elements[start].index.inputIndex == position.inputIndex { break }
      if elements[start].index.inputIndex > position.inputIndex { return }
      start += 1
    }
    guard start < elements.endIndex else { return }

    if case .complete = position.subIndex {
      // When removing a `.complete` position, we need to remove both the
      // complete element and any sub-elements with the same input index.

      // Remove up to the first element where the input index doesn't match.
      let end = elements[start...].firstIndex(where: { $0.index.inputIndex != position.inputIndex })
        ?? elements.endIndex

      remove(subrange: start..<end)
    } else {
      // When removing a `.sub` (i.e. non-`.complete`) position, we need to
      // also remove the `.complete` position, if it exists. Since `.complete`
      // positions always come before sub-positions, if one exists it  will be
      // the position found as `start`.
      if elements[start].index.subIndex == .complete {
        remove(at: start)
        start += 1
      }

      if let sub = elements[start...].firstIndex(where: { $0.index == position }) {
        remove(at: sub)
      }
    }
  }

  mutating func removeAll(in origin: InputOrigin) {
    origin.forEach {
      remove(at: $0)
    }
  }

  /// Removes the element(s) at the given position.
  ///
  /// - Note: This may remove multiple elements.
  mutating func remove(at origin: InputOrigin.Element) {
    guard case .argumentIndex(let i) = origin else { return }
    remove(at: i)
  }

  func coalescedExtraElements() -> [(InputOrigin, String)] {
    let completeIndexes: [InputIndex] = elements
      .compactMap {
        guard case .complete = $0.index.subIndex else { return nil }
        return $0.index.inputIndex
    }

    // Now return all non-terminator elements that are either:
    // 1) `.complete`
    // 2) `.sub` but not in `completeIndexes`

    let extraElements = elements.filter {
      if $0.isTerminator { return false }

      switch $0.index.subIndex {
      case .complete:
        return true
      case .sub:
        return !completeIndexes.contains($0.index.inputIndex)
      }
    }
    return extraElements.map { element -> (InputOrigin, String) in
      let input: String
      switch element.index.subIndex {
      case .complete:
        input = originalInput[element.index.inputIndex.rawValue]
      case .sub:
        if case .option(let option) = element.value {
          input = String(describing: option)
        } else {
          // Odd case. Fall back to entire input at that index:
          input = originalInput[element.index.inputIndex.rawValue]
        }
      }
      return (.init(argumentIndex: element.index), input)
    }
  }
}

func parseIndividualArg(_ arg: String, at position: Int) throws -> [SplitArguments.Element] {
  let index = SplitArguments.Index(inputIndex: .init(rawValue: position))
  if let nonDashIdx = arg.firstIndex(where: { $0 != "-" }) {
    let dashCount = arg.distance(from: arg.startIndex, to: nonDashIdx)
    let remainder = arg[nonDashIdx..<arg.endIndex]
    switch dashCount {
    case 0:
      return [.value(arg, index: index)]
    case 1:
      // Long option:
      let parsed = try ParsedArgument(longArgWithSingleDashRemainder: remainder)

      // Short options:
      let parts = parsed.subarguments
      switch parts.count {
      case 0:
        // This is a '-name=value' style argument
        return [.option(parsed, index: index)]
      case 1:
        // This is a single short '-n' style argument
        return [.option(.name(.short(remainder.first!)), index: index)]
      default:
        var result: [SplitArguments.Element] = [.option(parsed, index: index)]
        for (sub, a) in parts {
          var i = index
          i.subIndex = .sub(sub)
          result.append(.option(a, index: i))
        }
        return result
      }
    case 2:
      return [.option(ParsedArgument(arg), index: index)]
    default:
      throw ParserError.invalidOption(arg)
    }
  } else {
    // All dashes
    let dashCount = arg.count
    switch dashCount {
    case 0, 1:
      // Empty string or single dash
      return [.value(arg, index: index)]
    case 2:
      // We found the 1st "--". All the remaining are positional.
      return [.terminator(index: index)]
    default:
      throw ParserError.invalidOption(arg)
    }
  }
}

extension SplitArguments {
  /// Parses the given input into an array of `Element`.
  ///
  /// - Parameter arguments: The input from the command line.
  init(arguments: [String]) throws {
    self.init(originalInput: arguments)

    var position = 0
    var args = arguments[...]
    argLoop: while let arg = args.popFirst() {
      defer {
        position += 1
      }

      let parsedElements = try parseIndividualArg(arg, at: position)
      _elements.append(contentsOf: parsedElements)
      if parsedElements.first!.isTerminator {
        break
      }
    }

    for arg in args {
      let i = Index(inputIndex: InputIndex(rawValue: position))
      _elements.append(.value(arg, index: i))
      position += 1
    }
  }
}

private extension ParsedArgument {
  init(longArgRemainder remainder: Substring) throws {
    try self.init(longArgRemainder: remainder, makeName: { Name.long(String($0)) })
  }

  init(longArgWithSingleDashRemainder remainder: Substring) throws {
    try self.init(longArgRemainder: remainder, makeName: {
      /// If an argument has a single dash and single character,
      /// followed by a value, treat it as a short name.
      ///     `-c=1`      ->  `Name.short("c")`
      /// Otherwise, treat it as a long name with single dash.
      ///     `-count=1`  ->  `Name.longWithSingleDash("count")`
      $0.count == 1 ? Name.short($0.first!) : Name.longWithSingleDash(String($0))
    })
  }

  init(longArgRemainder remainder: Substring, makeName: (Substring) -> Name) throws {
    if let equalIdx = remainder.firstIndex(of: "=") {
      let name = remainder[remainder.startIndex..<equalIdx]
      guard !name.isEmpty else {
        throw ParserError.invalidOption(makeName(remainder).synopsisString)
      }
      let after = remainder.index(after: equalIdx)
      let value = String(remainder[after..<remainder.endIndex])
      self = .nameWithValue(makeName(name), value)
    } else {
      self = .name(makeName(remainder))
    }
  }

  static func shortOptions(shortArgRemainder: Substring) throws -> [ParsedArgument] {
    var result: [ParsedArgument] = []
    var remainder = shortArgRemainder
    while let char = remainder.popFirst() {
      guard char.isLetter || char.isNumber else {
        throw ParserError.nonAlphanumericShortOption(char)
      }
      result.append(.name(.short(char)))
    }
    return result
  }
}



// MARK: Usage


struct UsageGenerator {
  var toolName: String
  var definition: ArgumentSet
}

extension UsageGenerator {
  init(definition: ArgumentSet) {
    let toolName = CommandLine.arguments[0].split(separator: "/").last.map(String.init) ?? "<command>"
    self.init(toolName: toolName, definition: definition)
  }

  init(toolName: String, parsable: ParsableArguments, visibility: ArgumentVisibility, parent: InputKey?) {
    self.init(
      toolName: toolName,
      definition: ArgumentSet(type(of: parsable), visibility: visibility, parent: parent))
  }

  init(toolName: String, definition: [ArgumentSet]) {
    self.init(toolName: toolName, definition: ArgumentSet(sets: definition))
  }
}

extension UsageGenerator {
  /// The tool synopsis.
  ///
  /// In `roff`.
  var synopsis: String {
    var options = Array(definition)
    switch options.count {
    case 0:
      return toolName
    case let x where x > 12:
      // When we have too many options, keep required and positional arguments,
      // but discard the rest.
      options = options.filter {
        $0.isPositional || !$0.help.options.contains(.isOptional)
      }
      // If there are between 1 and 12 options left, print them, otherwise print
      // a simplified usage string.
      if !options.isEmpty, options.count <= 12 {
        let synopsis = options
          .map { $0.synopsis }
          .joined(separator: " ")
        return "\(toolName) [<options>] \(synopsis)"
      }
      return "\(toolName) <options>"
    default:
      let synopsis = options
        .map { $0.synopsis }
        .joined(separator: " ")
      return "\(toolName) \(synopsis)"
    }
  }
}

extension ArgumentDefinition {
  var synopsisForHelp: String {
    switch kind {
    case .named:
      let joinedSynopsisString = names
        .partitioned
        .map { $0.synopsisString }
        .joined(separator: ", ")

      switch update {
      case .unary:
        return "\(joinedSynopsisString) <\(valueName)>"
      case .nullary:
        return joinedSynopsisString
      }
    case .positional:
      return "<\(valueName)>"
    case .default:
      return ""
    }
  }

  var unadornedSynopsis: String {
    switch kind {
    case .named:
      guard let name = names.preferredName else {
        fatalError("preferredName cannot be nil for named arguments")
      }

      switch update {
      case .unary:
        return "\(name.synopsisString) <\(valueName)>"
      case .nullary:
        return name.synopsisString
      }
    case .positional:
      return "<\(valueName)>"
    case .default:
      return ""
    }
  }

  var synopsis: String {
    var synopsis = unadornedSynopsis
    if help.options.contains(.isRepeating) {
      synopsis += " ..."
    }
    if help.options.contains(.isOptional) {
      synopsis = "[\(synopsis)]"
    }
    if parsingStrategy == .postTerminator {
      synopsis = "-- \(synopsis)"
    }
    return synopsis
  }
}

extension ArgumentSet {
  /// Will generate a descriptive help message if possible.
  ///
  /// If no descriptive help message can be generated, `nil` will be returned.
  ///
  /// - Parameter error: the parse error that occurred.
  func errorDescription(error: Swift.Error) -> String? {
    switch error {
    case let parserError as ParserError:
      return ErrorMessageGenerator(arguments: self, error: parserError)
        .makeErrorMessage()
    case let commandError as CommandError:
      return ErrorMessageGenerator(arguments: self, error: commandError.parserError)
        .makeErrorMessage()
    default:
      return nil
    }
  }

  func helpDescription(error: Swift.Error) -> String? {
    switch error {
    case let parserError as ParserError:
      return ErrorMessageGenerator(arguments: self, error: parserError)
        .makeHelpMessage()
    case let commandError as CommandError:
      return ErrorMessageGenerator(arguments: self, error: commandError.parserError)
        .makeHelpMessage()
    default:
      return nil
    }
  }
}

struct ErrorMessageGenerator {
  var arguments: ArgumentSet
  var error: ParserError
}

extension ErrorMessageGenerator {
  func makeErrorMessage() -> String? {
    switch error {
    case .helpRequested, .versionRequested, .unknownOption:
      return nil

    case .notImplemented:
      return notImplementedMessage
    case .invalidState:
      return invalidState
    case .missingValueForOption(let o, let n):
      return missingValueForOptionMessage(origin: o, name: n)
    case .unexpectedValueForOption(let o, let n, let v):
      return unexpectedValueForOptionMessage(origin: o, name: n, value: v)
    case .unexpectedExtraValues(let v):
      return unexpectedExtraValuesMessage(values: v)
    case .duplicateExclusiveValues(previous: let previous, duplicate: let duplicate, originalInput: let arguments):
      return duplicateExclusiveValues(previous: previous, duplicate: duplicate, arguments: arguments)
    case .noValue(forKey: let k):
      return noValueMessage(key: k)
    case .unableToParseValue(let o, let n, let v, forKey: let k, originalError: let e):
      return unableToParseValueMessage(origin: o, name: n, value: v, key: k, error: e)
    case .invalidOption(let str):
      return "Invalid option: \(str)"
    case .nonAlphanumericShortOption(let c):
      return "Invalid option: -\(c)"
    case .missingSubcommand:
      return "Missing required subcommand."
    case .userValidationError(let error):
      switch error {
      case let error as LocalizedError:
        return error.errorDescription
      default:
        return String(describing: error)
      }
    case .noArguments(let error):
      switch error {
      case let error as ParserError:
        return ErrorMessageGenerator(arguments: self.arguments, error: error).makeErrorMessage()
      case let error as LocalizedError:
        return error.errorDescription
      default:
        return String(describing: error)
      }
    }
  }

  func makeHelpMessage() -> String? {
    switch error {
    case .unableToParseValue(let o, let n, let v, forKey: let k, originalError: let e):
      return unableToParseHelpMessage(origin: o, name: n, value: v, key: k, error: e)
    case .missingValueForOption(_, let n):
      return missingValueForOptionHelpMessage(name: n)
    case .noValue(let k):
      return noValueHelpMessage(key: k)
    default:
      return nil
    }
  }
}

extension ErrorMessageGenerator {
  func arguments(for key: InputKey) -> [ArgumentDefinition] {
    arguments
      .filter { $0.help.keys.contains(key) }
  }

  func help(for key: InputKey) -> ArgumentDefinition.Help? {
    arguments
      .first { $0.help.keys.contains(key) }
      .map { $0.help }
  }

  func valueName(for name: Name) -> String? {
    arguments
      .first { $0.names.contains(name) }
      .map { $0.valueName }
  }
}

extension ErrorMessageGenerator {
  var notImplementedMessage: String {
    return "Internal error. Parsing command-line arguments hit unimplemented code path."
  }
  var invalidState: String {
    return "Internal error. Invalid state while parsing command-line arguments."
  }


  func unknownOptionMessage(origin: InputOrigin.Element, name: Name) -> String {
    if case .short = name {
      return "Unknown option '\(name.synopsisString)'"
    }

    // An empirically derived magic number
    let SIMILARITY_FLOOR = 4

    let notShort: (Name) -> Bool = { (name: Name) in
      switch name {
      case .short: return false
      case .long: return true
      case .longWithSingleDash: return true
      }
    }
    let suggestion = arguments
      .flatMap({ $0.names })
      .filter({ $0.synopsisString.editDistance(to: name.synopsisString) < SIMILARITY_FLOOR }) // only include close enough suggestion
      .filter(notShort) // exclude short option suggestions
      .min(by: { lhs, rhs in // find the suggestion closest to the argument
        lhs.synopsisString.editDistance(to: name.synopsisString) < rhs.synopsisString.editDistance(to: name.synopsisString)
      })

    if let suggestion = suggestion {
      return "Unknown option '\(name.synopsisString)'. Did you mean '\(suggestion.synopsisString)'?"
    }
    return "Unknown option '\(name.synopsisString)'"
  }

  func missingValueForOptionMessage(origin: InputOrigin, name: Name) -> String {
    if let valueName = valueName(for: name) {
      return "Missing value for '\(name.synopsisString) <\(valueName)>'"
    } else {
      return "Missing value for '\(name.synopsisString)'"
    }
  }

  func unexpectedValueForOptionMessage(origin: InputOrigin.Element, name: Name, value: String) -> String? {
    return "The option '\(name.synopsisString)' does not take any value, but '\(value)' was specified."
  }

  func unexpectedExtraValuesMessage(values: [(InputOrigin, String)]) -> String? {
    switch values.count {
    case 0:
      return nil
    case 1:
      return "Unexpected argument '\(values.first!.1)'"
    default:
      let v = values.map { $0.1 }.joined(separator: "', '")
      return "\(values.count) unexpected arguments: '\(v)'"
    }
  }

  func duplicateExclusiveValues(previous: InputOrigin, duplicate: InputOrigin, arguments: [String]) -> String? {
    func elementString(_ origin: InputOrigin, _ arguments: [String]) -> String? {
      guard case .argumentIndex(let split) = origin.elements.first else { return nil }
      var argument = "\'\(arguments[split.inputIndex.rawValue])\'"
      if case let .sub(offsetIndex) = split.subIndex {
        let stringIndex = argument.index(argument.startIndex, offsetBy: offsetIndex+2)
        argument = "\'\(argument[stringIndex])\' in \(argument)"
      }
      return "flag \(argument)"
    }

    // Note that the RHS of these coalescing operators cannot be reached at this time.
    let dupeString = elementString(duplicate, arguments) ?? "position \(duplicate)"
    let origString = elementString(previous, arguments) ?? "position \(previous)"

    //TODO: review this message once environment values are supported.
    return "Value to be set with \(dupeString) had already been set with \(origString)"
  }

  func noValueMessage(key: InputKey) -> String? {
    let args = arguments(for: key)
    let possibilities: [String] = args.compactMap {
      $0.help.visibility.base == .default
        ? $0.nonOptional.synopsis
        : nil
    }
    switch possibilities.count {
    case 0:
      return "No value set for non-argument var \(key). Replace with a static variable, or let constant."
    case 1:
      return "Missing expected argument '\(possibilities.first!)'"
    default:
      let p = possibilities.joined(separator: "', '")
      return "Missing one of: '\(p)'"
    }
  }

  func unableToParseHelpMessage(origin: InputOrigin, name: Name?, value: String, key: InputKey, error: Error?) -> String {
    guard let abstract = help(for: key)?.abstract else { return "" }

    let valueName = arguments(for: key).first?.valueName

    switch (name, valueName) {
    case let (n?, v?):
      return "\(n.synopsisString) <\(v)>  \(abstract)"
    case let (_, v?):
      return "<\(v)>  \(abstract)"
    case (_, _):
      return ""
    }
  }

  func missingValueForOptionHelpMessage(name: Name) -> String {
    guard let arg = arguments.first(where: { $0.names.contains(name) }) else {
      return ""
    }

    let help = arg.help.abstract
    return "\(name.synopsisString) <\(arg.valueName)>  \(help)"
  }

  func noValueHelpMessage(key: InputKey) -> String {
    guard let abstract = help(for: key)?.abstract else { return "" }
    guard let arg = arguments(for: key).first else { return "" }

    if let synopsisString = arg.names.first?.synopsisString {
      return "\(synopsisString) <\(arg.valueName)>  \(abstract)"
    }
    return "<\(arg.valueName)>  \(abstract)"
  }

  func unableToParseValueMessage(origin: InputOrigin, name: Name?, value: String, key: InputKey, error: Error?) -> String {
    let argumentValue = arguments(for: key).first
    let valueName = argumentValue?.valueName

    // We want to make the "best effort" in producing a custom error message.
    // We favor `LocalizedError.errorDescription` and fall back to
    // `CustomStringConvertible`. To opt in, return your custom error message
    // as the `description` property of `CustomStringConvertible`.
    let customErrorMessage: String = {
      switch error {
      case let err as LocalizedError where err.errorDescription != nil:
        return ": " + err.errorDescription! // !!! Checked above that this will not be nil
      case let err?:
        return ": " + String(describing: err)
      default:
        return argumentValue?.formattedValueList ?? ""
      }
    }()

    switch (name, valueName) {
    case let (n?, v?):
      return "The value '\(value)' is invalid for '\(n.synopsisString) <\(v)>'\(customErrorMessage)"
    case let (_, v?):
      return "The value '\(value)' is invalid for '<\(v)>'\(customErrorMessage)"
    case let (n?, _):
      return "The value '\(value)' is invalid for '\(n.synopsisString)'\(customErrorMessage)"
    case (nil, nil):
      return "The value '\(value)' is invalid.\(customErrorMessage)"
    }
  }
}

private extension ArgumentDefinition {
  var formattedValueList: String {
    if help.allValues.isEmpty {
      return ""
    }

    if help.allValues.count < 6 {
      let quotedValues = help.allValues.map { "'\($0)'" }
      let validList: String
      if quotedValues.count <= 2 {
        validList = quotedValues.joined(separator: " and ")
      } else {
        validList = quotedValues.dropLast().joined(separator: ", ") + " or \(quotedValues.last!)"
      }
      return ". Please provide one of \(validList)."
    } else {
      let bulletValueList = help.allValues.map { "  - \($0)" }.joined(separator: "\n")
      return ". Please provide one of the following:\n\(bulletValueList)"
    }
  }
}


enum MessageInfo {
  case help(text: String)
  case validation(message: String, usage: String, help: String)
  case other(message: String, exitCode: ExitCode)

  init(error: Error, type: ParsableArguments.Type) {
    var commandStack: [ParsableCommand.Type]
    var parserError: ParserError? = nil

    switch error {
    case let e as CommandError:
      commandStack = e.commandStack
      parserError = e.parserError

      // Exit early on built-in requests
      switch e.parserError {
      case .helpRequested(let visibility):
        self = .help(text: HelpGenerator(commandStack: e.commandStack, visibility: visibility).rendered())
        return

      case .versionRequested:
        let versionString = commandStack
          .map { $0.configuration.version }
          .last(where: { !$0.isEmpty })
          ?? "Unspecified version"
        self = .help(text: versionString)
        return

      default:
        break
      }

    case let e as ParserError:
      // Send ParserErrors back through the CommandError path
      self.init(error: CommandError(commandStack: [type.asCommand], parserError: e), type: type)
      return

    default:
      commandStack = [type.asCommand]
      // if the error wasn't one of our two Error types, wrap it as a userValidationError
      // to be handled appropriately below
      parserError = .userValidationError(error)
    }

    var usage = HelpGenerator(commandStack: commandStack, visibility: .default).usageMessage()

    let commandNames = commandStack.map { $0._commandName }.joined(separator: " ")
    if let helpName = commandStack.getPrimaryHelpName() {
      if !usage.isEmpty {
        usage += "\n"
      }
      usage += "  See '\(commandNames) \(helpName.synopsisString)' for more information."
    }

    // Parsing errors and user-thrown validation errors have the usage
    // string attached. Other errors just get the error message.

    if case .userValidationError(let error) = parserError {
      switch error {
      case let error as ValidationError:
        self = .validation(message: error.message, usage: usage, help: "")
      case let error as CleanExit:
        switch error.base {
        case .helpRequest(let command):
          if let command = command {
            commandStack = CommandParser(type.asCommand).commandStack(for: command)
          }
          self = .help(text: HelpGenerator(commandStack: commandStack, visibility: .default).rendered())
        case .message(let message):
          self = .help(text: message)
        }
      case let exitCode as ExitCode:
        self = .other(message: "", exitCode: exitCode)
      case let error as LocalizedError where error.errorDescription != nil:
        self = .other(message: error.errorDescription!, exitCode: .failure)
      default:
        if Swift.type(of: error) is NSError.Type {
          self = .other(message: error.localizedDescription, exitCode: .failure)
        } else {
          self = .other(message: String(describing: error), exitCode: .failure)
        }
      }
    } else if let parserError = parserError {
      let usage: String = {
        guard case ParserError.noArguments = parserError else { return usage }
        return "\n" + HelpGenerator(commandStack: [type.asCommand], visibility: .default).rendered()
      }()
      let argumentSet = ArgumentSet(commandStack.last!, visibility: .default, parent: nil)
      let message = argumentSet.errorDescription(error: parserError) ?? ""
      let helpAbstract = argumentSet.helpDescription(error: parserError) ?? ""
      self = .validation(message: message, usage: usage, help: helpAbstract)
    } else {
      self = .other(message: String(describing: error), exitCode: .failure)
    }
  }

  var message: String {
    switch self {
    case .help(text: let text):
      return text
    case .validation(message: let message, usage: _, help: _):
      return message
    case .other(let message, _):
      return message
    }
  }

  func fullText(for args: ParsableArguments.Type) -> String {
    switch self {
    case .help(text: let text):
      return text
    case .validation(message: let message, usage: let usage, help: let help):
      let helpMessage = help.isEmpty ? "" : "Help:  \(help)\n"
      let errorMessage = message.isEmpty ? "" : "\(args._errorLabel): \(message)\n"
      return errorMessage + helpMessage + usage
    case .other(let message, _):
      return message.isEmpty ? "" : "\(args._errorLabel): \(message)"
    }
  }

  var shouldExitCleanly: Bool {
    switch self {
    case .help: return true
    case .validation, .other: return false
    }
  }

  var exitCode: ExitCode {
    switch self {
    case .help: return ExitCode.success
    case .validation: return ExitCode.validationFailure
    case .other(_, let exitCode): return exitCode
    }
  }
}

internal struct HelpGenerator {
  static var helpIndent = 2
  static var labelColumnWidth = 26
  static var systemScreenWidth: Int { Platform.terminalWidth }

  struct Section {
    struct Element: Hashable {
      var label: String
      var abstract: String = ""
      var discussion: String = ""

      var paddedLabel: String {
        String(repeating: " ", count: HelpGenerator.helpIndent) + label
      }

      func rendered(screenWidth: Int) -> String {
        let paddedLabel = self.paddedLabel
        let wrappedAbstract = self.abstract
          .wrapped(to: screenWidth, wrappingIndent: HelpGenerator.labelColumnWidth)
        let wrappedDiscussion = self.discussion.isEmpty
          ? ""
          : self.discussion.wrapped(to: screenWidth, wrappingIndent: HelpGenerator.helpIndent * 4) + "\n"
        let renderedAbstract: String = {
          guard !abstract.isEmpty else { return "" }
          if paddedLabel.count < HelpGenerator.labelColumnWidth {
            // Render after padded label.
            return String(wrappedAbstract.dropFirst(paddedLabel.count))
          } else {
            // Render in a new line.
            return "\n" + wrappedAbstract
          }
        }()
        return paddedLabel
          + renderedAbstract + "\n"
          + wrappedDiscussion
      }
    }

    enum Header: CustomStringConvertible, Equatable {
      case positionalArguments
      case subcommands
      case options
      case title(String)

      var description: String {
        switch self {
        case .positionalArguments:
          return "Arguments"
        case .subcommands:
          return "Subcommands"
        case .options:
          return "Options"
        case .title(let name):
          return name
        }
      }
    }

    var header: Header
    var elements: [Element]
    var discussion: String = ""
    var isSubcommands: Bool = false

    func rendered(screenWidth: Int) -> String {
      guard !elements.isEmpty else { return "" }

      let renderedElements = elements.map { $0.rendered(screenWidth: screenWidth) }.joined()
      return "\(String(describing: header).uppercased()):\n"
        + renderedElements
    }
  }

  struct DiscussionSection {
    var title: String = ""
    var content: String
  }

  var commandStack: [ParsableCommand.Type]
  var abstract: String
  var usage: String
  var sections: [Section]
  var discussionSections: [DiscussionSection]

  init(commandStack: [ParsableCommand.Type], visibility: ArgumentVisibility) {
    guard let currentCommand = commandStack.last else {
      fatalError()
    }

    let currentArgSet = ArgumentSet(currentCommand, visibility: visibility, parent: nil)
    self.commandStack = commandStack

    // Build the tool name and subcommand name from the command configuration
    var toolName = commandStack.map { $0._commandName }.joined(separator: " ")
    if let superName = commandStack.first!.configuration._superCommandName {
      toolName = "\(superName) \(toolName)"
    }

    if let usage = currentCommand.configuration.usage {
      self.usage = usage
    } else {
      var usage = UsageGenerator(toolName: toolName, definition: [currentArgSet])
        .synopsis
      if !currentCommand.configuration.subcommands.isEmpty {
        if usage.last != " " { usage += " " }
        usage += "<subcommand>"
      }
      self.usage = usage
    }

    self.abstract = currentCommand.configuration.abstract
    if !currentCommand.configuration.discussion.isEmpty {
      if !self.abstract.isEmpty {
        self.abstract += "\n"
      }
      self.abstract += "\n\(currentCommand.configuration.discussion)"
    }

    self.sections = HelpGenerator.generateSections(commandStack: commandStack, visibility: visibility)
    self.discussionSections = []
  }

  init(_ type: ParsableArguments.Type, visibility: ArgumentVisibility) {
    self.init(commandStack: [type.asCommand], visibility: visibility)
  }

  private static func generateSections(commandStack: [ParsableCommand.Type], visibility: ArgumentVisibility) -> [Section] {
    guard !commandStack.isEmpty else { return [] }

    var positionalElements: [Section.Element] = []
    var optionElements: [Section.Element] = []

    // Simulate an ordered dictionary using a dictionary and array for ordering.
    var titledSections: [String: [Section.Element]] = [:]
    var sectionTitles: [String] = []

    /// Start with a full slice of the ArgumentSet so we can peel off one or
    /// more elements at a time.
    var args = commandStack.argumentsForHelp(visibility: visibility)[...]
    while let arg = args.popFirst() {
      assert(arg.help.visibility.isAtLeastAsVisible(as: visibility))

      let synopsis: String
      let description: String

      if arg.help.isComposite {
        // If this argument is composite, we have a group of arguments to
        // output together.
        let groupEnd = args.firstIndex(where: { $0.help.keys != arg.help.keys }) ?? args.endIndex
        let groupedArgs = [arg] + args[..<groupEnd]
        args = args[groupEnd...]

        synopsis = groupedArgs
          .lazy
          .map { $0.synopsisForHelp }
          .joined(separator: "/")

        let defaultValue = arg.help.defaultValue
          .map { "(default: \($0))" } ?? ""

        let descriptionString = groupedArgs
          .lazy
          .map { $0.help.abstract }
          .first { !$0.isEmpty }

        description = [descriptionString, defaultValue]
          .lazy
          .compactMap { $0 }
          .filter { !$0.isEmpty }
          .joined(separator: " ")
      } else {
        synopsis = arg.synopsisForHelp

        let defaultValue = arg.help.defaultValue.flatMap { $0.isEmpty ? nil : "(default: \($0))" }
        description = [arg.help.abstract, defaultValue]
          .lazy
          .compactMap { $0 }
          .filter { !$0.isEmpty }
          .joined(separator: " ")
      }

      let element = Section.Element(label: synopsis, abstract: description, discussion: arg.help.discussion)
      switch (arg.kind, arg.help.parentTitle) {
      case (_, let sectionTitle) where !sectionTitle.isEmpty:
        if !titledSections.keys.contains(sectionTitle) {
          sectionTitles.append(sectionTitle)
        }
        titledSections[sectionTitle, default: []].append(element)
      case (.positional, _):
        positionalElements.append(element)
      default:
        optionElements.append(element)
      }
    }

    let configuration = commandStack.last!.configuration
    let subcommandElements: [Section.Element] =
      configuration.subcommands.compactMap { command in
        guard command.configuration.shouldDisplay else { return nil }
        var label = command._commandName
        if command == configuration.defaultSubcommand {
            label += " (default)"
        }
        return Section.Element(
          label: label,
          abstract: command.configuration.abstract)
    }

    // Combine the compiled groups in this order:
    // - arguments
    // - named sections
    // - options/flags
    // - subcommands
    return [
      Section(header: .positionalArguments, elements: positionalElements),
    ] + sectionTitles.map { name in
      Section(header: .title(name), elements: titledSections[name, default: []])
    } + [
      Section(header: .options, elements: optionElements),
      Section(header: .subcommands, elements: subcommandElements),
    ]
  }

  func usageMessage() -> String {
    guard !usage.isEmpty else { return "" }
    return "Usage: \(usage.hangingIndentingEachLine(by: 7))"
  }

  var includesSubcommands: Bool {
    guard let subcommandSection = sections.first(where: { $0.header == .subcommands })
      else { return false }
    return !subcommandSection.elements.isEmpty
  }

  func rendered(screenWidth: Int? = nil) -> String {
    let screenWidth = screenWidth ?? HelpGenerator.systemScreenWidth
    let renderedSections = sections
      .map { $0.rendered(screenWidth: screenWidth) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    let renderedAbstract = abstract.isEmpty
      ? ""
      : "OVERVIEW: \(abstract)".wrapped(to: screenWidth) + "\n\n"

    var helpSubcommandMessage = ""
    if includesSubcommands {
      var names = commandStack.map { $0._commandName }
      if let superName = commandStack.first!.configuration._superCommandName {
        names.insert(superName, at: 0)
      }
      names.insert("help", at: 1)

      helpSubcommandMessage = """

          See '\(names.joined(separator: " ")) <subcommand>' for detailed help.
        """
    }

    let renderedUsage = usage.isEmpty
      ? ""
      : "USAGE: \(usage.hangingIndentingEachLine(by: 7))\n\n"

    return """
    \(renderedAbstract)\
    \(renderedUsage)\
    \(renderedSections)\(helpSubcommandMessage)
    """
  }
}

fileprivate extension CommandConfiguration {
  static var defaultHelpNames: NameSpecification { [.short, .long] }
}

fileprivate extension NameSpecification {
  /// Generates a list of `Name`s for the help command at any visibility level.
  ///
  /// If the `default` visibility is used, the help names are returned
  /// unmodified. If a non-default visibility is used the short names are
  /// removed and the long names (both single and double dash) are appended with
  /// the name of the visibility level. After the optional name modification
  /// step, the name are returned in descending order.
  func generateHelpNames(visibility: ArgumentVisibility) -> [Name] {
    self
      .makeNames(InputKey(name: "help", parent: nil))
      .compactMap { name in
        guard visibility.base != .default else { return name }
        switch name {
        case .long(let helpName):
          return .long("\(helpName)-\(visibility.base)")
        case .longWithSingleDash(let helpName):
          return .longWithSingleDash("\(helpName)-\(visibility)")
        case .short:
          // Cannot create a non-default help flag from a short name.
          return nil
        }
      }
      .sorted(by: >)
  }
}

internal extension BidirectionalCollection where Element == ParsableCommand.Type {
  /// Returns a list of help names at the request visibility level for the top
  /// most ParsableCommand in the command stack with custom helpNames. If the
  /// command stack contains no custom help names the default help names.
  func getHelpNames(visibility: ArgumentVisibility) -> [Name] {
    self.last(where: { $0.configuration.helpNames != nil })
      .map { $0.configuration.helpNames!.generateHelpNames(visibility: visibility) }
      ?? CommandConfiguration.defaultHelpNames.generateHelpNames(visibility: visibility)
  }

  func getPrimaryHelpName() -> Name? {
    getHelpNames(visibility: .default).preferredName
  }

  func versionArgumentDefinition() -> ArgumentDefinition? {
    guard contains(where: { !$0.configuration.version.isEmpty })
      else { return nil }
    return ArgumentDefinition(
      kind: .named([.long("version")]),
      help: .init(
        allValues: [],
        options: [.isOptional],
        help: "Show the version.",
        defaultValue: nil,
        key: InputKey(name: "", parent: nil),
        isComposite: false),
      completion: .default,
      update: .nullary({ _, _, _ in })
    )
  }

  func helpArgumentDefinition() -> ArgumentDefinition? {
    let names = getHelpNames(visibility: .default)
    guard !names.isEmpty else { return nil }
    return ArgumentDefinition(
      kind: .named(names),
      help: .init(
        allValues: [],
        options: [.isOptional],
        help: "Show help information.",
        defaultValue: nil,
        key: InputKey(name: "", parent: nil),
        isComposite: false),
      completion: .default,
      update: .nullary({ _, _, _ in })
    )
  }

  func dumpHelpArgumentDefinition() -> ArgumentDefinition {
    return ArgumentDefinition(
      kind: .named([.long("experimental-dump-help")]),
      help: .init(
        allValues: [],
        options: [.isOptional],
        help: ArgumentHelp("Dump help information as JSON."),
        defaultValue: nil,
        key: InputKey(name: "", parent: nil),
        isComposite: false),
      completion: .default,
      update: .nullary({ _, _, _ in })
    )
  }

  /// Returns the ArgumentSet for the last command in this stack, including
  /// help and version flags, when appropriate.
  func argumentsForHelp(visibility: ArgumentVisibility) -> ArgumentSet {
    guard var arguments = self.last.map({ ArgumentSet($0, visibility: visibility, parent: nil) })
      else { return ArgumentSet() }
    self.versionArgumentDefinition().map { arguments.append($0) }
    self.helpArgumentDefinition().map { arguments.append($0) }

    // To add when 'dump-help' is public API:
    // arguments.append(self.dumpHelpArgumentDefinition())

    return arguments
  }
}

struct HelpCommand: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "help",
    abstract: "Show subcommand help information.",
    helpNames: [])

  /// Any subcommand names provided after the `help` subcommand.
  @Argument var subcommands: [String] = []

  /// Capture and ignore any extra help flags given by the user.
  @Flag(name: [.short, .long, .customLong("help", withSingleDash: true)], help: .private)
  var help = false

  private(set) var commandStack: [ParsableCommand.Type] = []
  private(set) var visibility: ArgumentVisibility = .default

  init() {}

  mutating func run() throws {
    throw CommandError(
      commandStack: commandStack,
      parserError: .helpRequested(visibility: visibility))
  }

  mutating func buildCommandStack(with parser: CommandParser) throws {
    commandStack = parser.commandStack(for: subcommands)
  }

  /// Used for testing.
  func generateHelp(screenWidth: Int) -> String {
    HelpGenerator(
      commandStack: commandStack,
      visibility: visibility)
      .rendered(screenWidth: screenWidth)
  }

  enum CodingKeys: CodingKey {
    case subcommands
    case help
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.subcommands = try container.decode([String].self, forKey: .subcommands)
    self.help = try container.decode(Bool.self, forKey: .help)
  }

  init(commandStack: [ParsableCommand.Type], visibility: ArgumentVisibility) {
    self.commandStack = commandStack
    self.visibility = visibility
    self.subcommands = commandStack.map { $0._commandName }
    self.help = false
  }
}



// MARK: Parsable Properties


/// A property wrapper that represents a positional command-line argument.
///
/// Use the `@Argument` wrapper to define a property of your custom command as
/// a positional argument. A *positional argument* for a command-line tool is
/// specified without a label and must appear in declaration order. `@Argument`
/// properties with `Optional` type or a default value are optional for the user
/// of your command-line tool.
///
/// For example, the following program has two positional arguments. The `name`
/// argument is required, while `greeting` is optional because it has a default
/// value.
///
///     @main
///     struct Greet: ParsableCommand {
///         @Argument var name: String
///         @Argument var greeting: String = "Hello"
///
///         mutating func run() {
///             print("\(greeting) \(name)!")
///         }
///     }
///
/// You can call this program with just a name or with a name and a
/// greeting. When you supply both arguments, the first argument is always
/// treated as the name, due to the order of the property declarations.
///
///     $ greet Nadia
///     Hello Nadia!
///     $ greet Tamara Hi
///     Hi Tamara!
@propertyWrapper
public struct Argument<Value>:
  Decodable, ParsedWrapper
{
  internal var _parsedValue: Parsed<Value>

  internal init(_parsedValue: Parsed<Value>) {
    self._parsedValue = _parsedValue
  }

  public init(from decoder: Decoder) throws {
    try self.init(_decoder: decoder)
  }

  /// This initializer works around a quirk of property wrappers, where the
  /// compiler will not see no-argument initializers in extensions. Explicitly
  /// marking this initializer unavailable means that when `Value` conforms to
  /// `ExpressibleByArgument`, that overload will be selected instead.
  ///
  /// ```swift
  /// @Argument() var foo: String // Syntax without this initializer
  /// @Argument var foo: String   // Syntax with this initializer
  /// ```
  @available(*, unavailable, message: "A default value must be provided unless the value type conforms to ExpressibleByArgument.")
  public init() {
    fatalError("unavailable")
  }

  /// The value presented by this property wrapper.
  public var wrappedValue: Value {
    get {
      switch _parsedValue {
      case .value(let v):
        return v
      case .definition:
        fatalError(directlyInitializedError)
      }
    }
    set {
      _parsedValue = .value(newValue)
    }
  }
}

extension Argument: CustomStringConvertible {
  public var description: String {
    switch _parsedValue {
    case .value(let v):
      return String(describing: v)
    case .definition:
      return "Argument(*definition*)"
    }
  }
}

extension Argument: DecodableParsedWrapper where Value: Decodable { }

/// The strategy to use when parsing multiple values from positional arguments
/// into an array.
public struct ArgumentArrayParsingStrategy: Hashable {
  internal var base: ArgumentDefinition.ParsingStrategy

  /// Parse only unprefixed values from the command-line input, ignoring
  /// any inputs that have a dash prefix. This is the default strategy.
  ///
  /// `remaining` is the default parsing strategy for argument arrays.
  ///
  /// For example, the `Example` command defined below has a `words` array that
  /// uses the `remaining` parsing strategy:
  ///
  ///     @main
  ///     struct Example: ParsableCommand {
  ///         @Flag var verbose = false
  ///
  ///         @Argument(parsing: .remaining)
  ///         var words: [String]
  ///
  ///         func run() {
  ///             print(words.joined(separator: "\n"))
  ///         }
  ///     }
  ///
  /// Any non-dash-prefixed inputs will be captured in the `words` array.
  ///
  /// ```
  /// $ example --verbose one two
  /// one
  /// two
  /// $ example one two --verbose
  /// one
  /// two
  /// $ example one two --other
  /// Error: Unknown option '--other'
  /// ```
  ///
  /// If a user uses the `--` terminator in their input, all following inputs
  /// will be captured in `words`.
  ///
  /// ```
  /// $ example one two -- --verbose --other
  /// one
  /// two
  /// --verbose
  /// --other
  /// ```
  public static var remaining: ArgumentArrayParsingStrategy {
    self.init(base: .default)
  }

  /// After parsing, capture all unrecognized inputs in this argument array.
  ///
  /// You can use the `allUnrecognized` parsing strategy to suppress
  /// "unexpected argument" errors or to capture unrecognized inputs for further
  /// processing.
  ///
  /// For example, the `Example` command defined below has an `other` array that
  /// uses the `allUnrecognized` parsing strategy:
  ///
  ///     @main
  ///     struct Example: ParsableCommand {
  ///         @Flag var verbose = false
  ///         @Argument var name: String
  ///
  ///         @Argument(parsing: .allUnrecognized)
  ///         var other: [String]
  ///
  ///         func run() {
  ///             print(other.joined(separator: "\n"))
  ///         }
  ///     }
  ///
  /// After parsing the `--verbose` flag and `<name>` argument, any remaining
  /// input is captured in the `other` array.
  ///
  /// ```
  /// $ example --verbose Negin one two
  /// one
  /// two
  /// $ example Asa --verbose --other -zzz
  /// --other
  /// -zzz
  /// ```
  public static var allUnrecognized: ArgumentArrayParsingStrategy {
    self.init(base: .allUnrecognized)
  }

  /// Before parsing, capture all inputs that follow the `--` terminator in this
  /// argument array.
  ///
  /// For example, the `Example` command defined below has a `words` array that
  /// uses the `postTerminator` parsing strategy:
  ///
  ///     @main
  ///     struct Example: ParsableCommand {
  ///         @Flag var verbose = false
  ///         @Argument var name = ""
  ///
  ///         @Argument(parsing: .postTerminator)
  ///         var words: [String]
  ///
  ///         func run() {
  ///             print(words.joined(separator: "\n"))
  ///         }
  ///     }
  ///
  /// Before looking for the `--verbose` flag and `<name>` argument, any inputs
  /// after the `--` terminator are captured into the `words` array.
  ///
  /// ```
  /// $ example --verbose Asa -- one two --other
  /// one
  /// two
  /// --other
  /// $ example Asa Extra -- one two --other
  /// Error: Unexpected argument 'Extra'
  /// ```
  ///
  /// - Note: This parsing strategy can be surprising for users, since it
  ///   changes the behavior of the `--` terminator. Prefer ``remaining``
  ///   whenever possible.
  public static var postTerminator: ArgumentArrayParsingStrategy {
    self.init(base: .postTerminator)
  }

  /// Parse all remaining inputs after parsing any known options or flags,
  /// including dash-prefixed inputs and the `--` terminator.
  ///
  /// You can use the `captureForPassthrough` parsing strategy if you need to
  /// capture a user's input to manually pass it unchanged to another command.
  ///
  /// When you use this parsing strategy, the parser stops parsing flags and
  /// options as soon as it encounters a positional argument or an unrecognized
  /// flag, and captures all remaining inputs in the array argument.
  ///
  /// For example, the `Example` command defined below has an `words` array that
  /// uses the `captureForPassthrough` parsing strategy:
  ///
  ///     @main
  ///     struct Example: ParsableCommand {
  ///         @Flag var verbose = false
  ///
  ///         @Argument(parsing: .captureForPassthrough)
  ///         var words: [String] = []
  ///
  ///         func run() {
  ///             print(words.joined(separator: "\n"))
  ///         }
  ///     }
  ///
  /// Any values after the first unrecognized input are captured in the `words`
  /// array.
  ///
  /// ```
  /// $ example --verbose one two --other
  /// one
  /// two
  /// --other
  /// $ example one two --verbose
  /// one
  /// two
  /// --verbose
  /// ```
  ///
  /// With the `captureForPassthrough` parsing strategy, the `--` terminator
  /// is included in the captured values.
  ///
  /// ```
  /// $ example --verbose one two -- --other
  /// one
  /// two
  /// --
  /// --other
  /// ```
  ///
  /// - Note: This parsing strategy can be surprising for users, particularly
  ///   when combined with options and flags. Prefer ``remaining`` or
  ///   ``allUnrecognized`` whenever possible, since users can always terminate
  ///   options and flags with the `--` terminator. With the `remaining`
  ///   parsing strategy, the input `--verbose -- one two --other` would have
  ///   the same result as the first example above.
  public static var captureForPassthrough: ArgumentArrayParsingStrategy {
    self.init(base: .allRemainingInput)
  }

  @available(*, deprecated, renamed: "captureForPassthrough")
  public static var unconditionalRemaining: ArgumentArrayParsingStrategy {
    .captureForPassthrough
  }
}

// MARK: - @Argument T: ExpressibleByArgument Initializers
extension Argument where Value: ExpressibleByArgument {
  /// Creates a property with a default value provided by standard Swift default
  /// value syntax.
  ///
  /// This method is called to initialize an `Argument` with a default value
  /// such as:
  /// ```swift
  /// @Argument var foo: String = "bar"
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property, provided
  ///   implicitly by the compiler during property wrapper initialization.
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  public init(
    wrappedValue: Value,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates a property with no default value.
  ///
  /// This method is called to initialize an `Argument` without a default value
  /// such as:
  /// ```swift
  /// @Argument var foo: String
  /// ```
  ///
  /// - Parameters:
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  public init(
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Argument T Initializers
extension Argument {
  /// Creates a property with a default value provided by standard Swift default
  /// value syntax, parsing with the given closure.
  ///
  /// This method is called to initialize an `Argument` with a default value
  /// such as:
  /// ```swift
  /// @Argument(transform: baz)
  /// var foo: String = "bar"
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property, provided
  ///     implicitly by the compiler during property wrapper initialization.
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's type
  ///     or throws an error.
  public init(
    wrappedValue: Value,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> Value
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        transform: transform,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates a property with no default value, parsing with the given closure.
  ///
  /// This method is called to initialize an `Argument` with no default value such as:
  /// ```swift
  /// @Argument(transform: baz)
  /// var foo: String
  /// ```
  ///
  /// - Parameters:
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init(
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> Value
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Argument Optional<T: ExpressibleByArgument> Initializers
extension Argument {
  /// This initializer allows a user to provide a `nil` default value for an
  /// optional `@Argument`-marked property without allowing a non-`nil` default
  /// value.
  ///
  /// - Parameters:
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    wrappedValue _value: _OptionalNilComparisonType,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  @available(*, deprecated, message: """
    Optional @Arguments with default values should be declared as non-Optional.
    """)
  @_disfavoredOverload
  public init<T>(
    wrappedValue _wrappedValue: Optional<T>,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        initial: _wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates an optional property that reads its value from an argument.
  ///
  /// The argument is optional for the caller of the command and defaults to
  /// `nil`.
  ///
  /// - Parameters:
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Argument Optional<T> Initializers
extension Argument {
  /// This initializer allows a user to provide a `nil` default value for an
  /// optional `@Argument`-marked property without allowing a non-`nil` default
  /// value.
  ///
  /// - Parameters:
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init<T>(
    wrappedValue _value: _OptionalNilComparisonType,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  @available(*, deprecated, message: """
    Optional @Arguments with default values should be declared as non-Optional.
    """)
  @_disfavoredOverload
  public init<T>(
    wrappedValue _wrappedValue: Optional<T>,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        transform: transform,
        initial: _wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates an optional property that reads its value from an argument.
  ///
  /// The argument is optional for the caller of the command and defaults to
  /// `nil`.
  ///
  /// - Parameters:
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init<T>(
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: .default,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Argument Array<T: ExpressibleByArgument> Initializers
extension Argument {
  /// Creates a property that reads an array from zero or more arguments.
  ///
  /// - Parameters:
  ///   - initial: A default value to use for this property.
  ///   - parsingStrategy: The behavior to use when parsing multiple values from
  ///     the command-line arguments.
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    wrappedValue: Array<T>,
    parsing parsingStrategy: ArgumentArrayParsingStrategy = .remaining,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates a property with no default value that reads an array from zero or
  /// more arguments.
  ///
  /// This method is called to initialize an array `Argument` with no default
  /// value such as:
  /// ```swift
  /// @Argument()
  /// var foo: [String]
  /// ```
  ///
  /// - Parameters:
  ///   - parsingStrategy: The behavior to use when parsing multiple values from
  ///   the command-line arguments.
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    parsing parsingStrategy: ArgumentArrayParsingStrategy = .remaining,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Argument Array<T> Initializers
extension Argument {
  /// Creates a property that reads an array from zero or more arguments,
  /// parsing each element with the given closure.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property.
  ///   - parsingStrategy: The behavior to use when parsing multiple values from
  ///     the command-line arguments.
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init<T>(
    wrappedValue: Array<T>,
    parsing parsingStrategy: ArgumentArrayParsingStrategy = .remaining,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates a property with no default value that reads an array from zero or
  /// more arguments, parsing each element with the given closure.
  ///
  /// This method is called to initialize an array `Argument` with no default
  /// value such as:
  /// ```swift
  /// @Argument(transform: baz)
  /// var foo: [String]
  /// ```
  ///
  /// - Parameters:
  ///   - parsingStrategy: The behavior to use when parsing multiple values from
  ///     the command-line arguments.
  ///   - help: Information about how to use this argument.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init<T>(
    parsing parsingStrategy: ArgumentArrayParsingStrategy = .remaining,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .positional,
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

/// Help information for a command-line argument.
public struct ArgumentHelp {
  /// A short description of the argument.
  public var abstract: String = ""

  /// An expanded description of the argument, in plain text form.
  public var discussion: String = ""

  /// An alternative name to use for the argument's value when showing usage
  /// information.
  ///
  /// - Note: This property is ignored when generating help for flags, since
  ///   flags don't include a value.
  public var valueName: String?

  /// A visibility level indicating whether this argument should be shown in
  /// the extended help display.
  public var visibility: ArgumentVisibility = .default

  /// A Boolean value indicating whether this argument should be shown in
  /// the extended help display.
  @available(*, deprecated, message: "Use visibility level instead.")
  public var shouldDisplay: Bool {
    get {
      return visibility.base == .default
    }
    set {
      visibility = newValue ? .default : .hidden
    }
  }

  /// Creates a new help instance.
  @available(*, deprecated, message: "Use init(_:discussion:valueName:visibility:) instead.")
  public init(
    _ abstract: String = "",
    discussion: String = "",
    valueName: String? = nil,
    shouldDisplay: Bool)
  {
    self.abstract = abstract
    self.discussion = discussion
    self.valueName = valueName
    self.shouldDisplay = shouldDisplay
  }

  /// Creates a new help instance.
  public init(
    _ abstract: String = "",
    discussion: String = "",
    valueName: String? = nil,
    visibility: ArgumentVisibility = .default)
  {
    self.abstract = abstract
    self.discussion = discussion
    self.valueName = valueName
    self.visibility = visibility
  }

  /// A `Help` instance that shows an argument only in the extended help display.
  public static var hidden: ArgumentHelp {
    ArgumentHelp(visibility: .hidden)
  }

  /// A `Help` instance that hides an argument from the extended help display.
  public static var `private`: ArgumentHelp {
    ArgumentHelp(visibility: .private)
  }
}

extension ArgumentHelp: ExpressibleByStringInterpolation {
  public init(stringLiteral value: String) {
    self.abstract = value
  }
}

/// Visibility level of an argument's help.
public struct ArgumentVisibility: Hashable {
  /// Internal implementation of `ArgumentVisibility` to allow for easier API
  /// evolution.
  internal enum Representation {
    case `default`
    case hidden
    case `private`
  }

  internal var base: Representation

  /// Show help for this argument whenever appropriate.
  public static let `default` = Self(base: .default)

  /// Only show help for this argument in the extended help screen.
  public static let hidden = Self(base: .hidden)

  /// Never show help for this argument.
  public static let `private` = Self(base: .private)
}

extension ArgumentVisibility.Representation {
  /// A raw Integer value that represents each visibility level.
  ///
  /// `_comparableLevel` can be used to test if a Visibility case is more or
  /// less visible than another, without committing this behavior to API.
  /// A lower `_comparableLevel` indicates that the case is less visible (more
  /// secret).
  internal var _comparableLevel: Int {
    switch self {
    case .default:
      return 2
    case .hidden:
      return 1
    case .private:
      return 0
    }
  }
}

extension ArgumentVisibility {
  /// - Returns: true if `self` is at least as visible as the supplied argument.
  internal func isAtLeastAsVisible(as other: Self) -> Bool {
    self.base._comparableLevel >= other.base._comparableLevel
  }
}

/// The type of completion to use for an argument or option.
public struct CompletionKind {
  internal enum Kind {
    /// Use the default completion kind for the value's type.
    case `default`

    /// Use the specified list of completion strings.
    case list([String])

    /// Complete file names with the specified extensions.
    case file(extensions: [String])

    /// Complete directory names that match the specified pattern.
    case directory

    /// Call the given shell command to generate completions.
    case shellCommand(String)

    /// Generate completions using the given closure.
    case custom(([String]) -> [String])
  }

  internal var kind: Kind

  /// Use the default completion kind for the value's type.
  public static var `default`: CompletionKind {
    CompletionKind(kind: .default)
  }

  /// Use the specified list of completion strings.
  public static func list(_ words: [String]) -> CompletionKind {
    CompletionKind(kind: .list(words))
  }

  /// Complete file names.
  public static func file(extensions: [String] = []) -> CompletionKind {
    CompletionKind(kind: .file(extensions: extensions))
  }

  /// Complete directory names.
  public static var directory: CompletionKind {
    CompletionKind(kind: .directory)
  }

  /// Call the given shell command to generate completions.
  public static func shellCommand(_ command: String) -> CompletionKind {
    CompletionKind(kind: .shellCommand(command))
  }

  /// Generate completions using the given closure.
  public static func custom(_ completion: @escaping ([String]) -> [String]) -> CompletionKind {
    CompletionKind(kind: .custom(completion))
  }
}

/// An error type that is presented to the user as an error with parsing their
/// command-line input.
public struct ValidationError: Error, CustomStringConvertible {
  /// The error message represented by this instance, this string is presented to
  /// the user when a `ValidationError` is thrown from either; `run()`,
  /// `validate()` or a transform closure.
  public internal(set) var message: String

  /// Creates a new validation error with the given message.
  public init(_ message: String) {
    self.message = message
  }

  public var description: String {
    message
  }
}

/// An error type that only includes an exit code.
///
/// If you're printing custom error messages yourself, you can throw this error
/// to specify the exit code without adding any additional output to standard
/// out or standard error.
public struct ExitCode: Error, RawRepresentable, Hashable {
  /// The exit code represented by this instance.
  public var rawValue: Int32

  /// Creates a new `ExitCode` with the given code.
  public init(_ code: Int32) {
    self.rawValue = code
  }

  public init(rawValue: Int32) {
    self.init(rawValue)
  }

  /// An exit code that indicates successful completion of a command.
  public static let success = ExitCode(Platform.exitCodeSuccess)

  /// An exit code that indicates that the command failed.
  public static let failure = ExitCode(Platform.exitCodeFailure)

  /// An exit code that indicates that the user provided invalid input.
  public static let validationFailure = ExitCode(Platform.exitCodeValidationFailure)

  /// A Boolean value indicating whether this exit code represents the
  /// successful completion of a command.
  public var isSuccess: Bool {
    self == Self.success
  }
}

/// An error type that represents a clean (i.e. non-error state) exit of the
/// utility.
///
/// Throwing a `CleanExit` instance from a `validate` or `run` method, or
/// passing it to `exit(with:)`, exits the program with exit code `0`.
public struct CleanExit: Error, CustomStringConvertible {
  internal enum Representation {
    case helpRequest(ParsableCommand.Type? = nil)
    case message(String)
  }

  internal var base: Representation

  /// Treat this error as a help request and display the full help message.
  ///
  /// You can use this case to simulate the user specifying one of the help
  /// flags or subcommands.
  ///
  /// - Parameter command: The command type to offer help for, if different
  ///   from the root command.
  public static func helpRequest(_ type: ParsableCommand.Type? = nil) -> CleanExit {
    self.init(base: .helpRequest(type))
  }

  /// Treat this error as a clean exit with the given message.
  public static func message(_ text: String) -> CleanExit {
    self.init(base: .message(text))
  }

  /// Treat this error as a help request and display the full help message.
  ///
  /// You can use this case to simulate the user specifying one of the help
  /// flags or subcommands.
  ///
  /// - Parameter command: A command to offer help for, if different from
  ///   the root command.
  public static func helpRequest(_ command: ParsableCommand) -> CleanExit {
    return .helpRequest(type(of: command))
  }

  public var description: String {
    switch self.base {
    case .helpRequest: return "--help"
    case .message(let message): return message
    }
  }
}

/// A property wrapper that represents a command-line flag.
///
/// Use the `@Flag` wrapper to define a property of your custom type as a
/// command-line flag. A *flag* is a dash-prefixed label that can be provided on
/// the command line, such as `-d` and `--debug`.
///
/// For example, the following program declares a flag that lets a user indicate
/// that seconds should be included when printing the time.
///
///     @main
///     struct Time: ParsableCommand {
///         @Flag var includeSeconds = false
///
///         mutating func run() {
///             if includeSeconds {
///                 print(Date.now.formatted(.dateTime.hour().minute().second()))
///             } else {
///                 print(Date.now.formatted(.dateTime.hour().minute()))
///             }
///         }
///     }
///
/// `includeSeconds` has a default value of `false`, but becomes `true` if
/// `--include-seconds` is provided on the command line.
///
///     $ time
///     11:09 AM
///     $ time --include-seconds
///     11:09:15 AM
///
/// A flag can have a value that is a `Bool`, an `Int`, or any `EnumerableFlag`
/// type. When using an `EnumerableFlag` type as a flag, the individual cases
/// form the flags that are used on the command line.
///
///     @main
///     struct Math: ParsableCommand {
///         enum Operation: EnumerableFlag {
///             case add
///             case multiply
///         }
///
///         @Flag var operation: Operation
///
///         mutating func run() {
///             print("Time to \(operation)!")
///         }
///     }
///
/// Instead of using the name of the `operation` property as the flag in this
/// case, the two cases of the `Operation` enumeration become valid flags.
/// The `operation` property is neither optional nor given a default value, so
/// one of the two flags is required.
///
///     $ math --add
///     Time to add!
///     $ math
///     Error: Missing one of: '--add', '--multiply'
@propertyWrapper
public struct Flag<Value>: Decodable, ParsedWrapper {
  internal var _parsedValue: Parsed<Value>

  internal init(_parsedValue: Parsed<Value>) {
    self._parsedValue = _parsedValue
  }

  public init(from decoder: Decoder) throws {
    try self.init(_decoder: decoder)
  }

  /// This initializer works around a quirk of property wrappers, where the
  /// compiler will not see no-argument initializers in extensions. Explicitly
  /// marking this initializer unavailable means that when `Value` is a type
  /// supported by `Flag` like `Bool` or `EnumerableFlag`, the appropriate
  /// overload will be selected instead.
  ///
  /// ```swift
  /// @Flag() var flag: Bool  // Syntax without this initializer
  /// @Flag var flag: Bool    // Syntax with this initializer
  /// ```
  @available(*, unavailable, message: "A default value must be provided unless the value type is supported by Flag.")
  public init() {
    fatalError("unavailable")
  }

  /// The value presented by this property wrapper.
  public var wrappedValue: Value {
    get {
      switch _parsedValue {
      case .value(let v):
        return v
      case .definition:
        fatalError(directlyInitializedError)
      }
    }
    set {
      _parsedValue = .value(newValue)
    }
  }
}

extension Flag: CustomStringConvertible {
  public var description: String {
    switch _parsedValue {
    case .value(let v):
      return String(describing: v)
    case .definition:
      return "Flag(*definition*)"
    }
  }
}

extension Flag: DecodableParsedWrapper where Value: Decodable {}

/// The options for converting a Boolean flag into a `true`/`false` pair.
public struct FlagInversion: Hashable {
  internal enum Representation {
    case prefixedNo
    case prefixedEnableDisable
  }

  internal var base: Representation

  /// Adds a matching flag with a `no-` prefix to represent `false`.
  ///
  /// For example, the `shouldRender` property in this declaration is set to
  /// `true` when a user provides `--render` and to `false` when the user
  /// provides `--no-render`:
  ///
  ///     @Flag(name: .customLong("render"), inversion: .prefixedNo)
  ///     var shouldRender: Bool
  public static var prefixedNo: FlagInversion {
    self.init(base: .prefixedNo)
  }

  /// Uses matching flags with `enable-` and `disable-` prefixes.
  ///
  /// For example, the `extraOutput` property in this declaration is set to
  /// `true` when a user provides `--enable-extra-output` and to `false` when
  /// the user provides `--disable-extra-output`:
  ///
  ///     @Flag(inversion: .prefixedEnableDisable)
  ///     var extraOutput: Bool
  public static var prefixedEnableDisable: FlagInversion {
    self.init(base: .prefixedEnableDisable)
  }
}

/// The options for treating enumeration-based flags as exclusive.
public struct FlagExclusivity: Hashable {
  internal enum Representation {
    case exclusive
    case chooseFirst
    case chooseLast
  }

  internal var base: Representation

  /// Only one of the enumeration cases may be provided.
  public static var exclusive: FlagExclusivity {
    self.init(base: .exclusive)
  }

  /// The first enumeration case that is provided is used.
  public static var chooseFirst: FlagExclusivity {
    self.init(base: .chooseFirst)
  }

  /// The last enumeration case that is provided is used.
  public static var chooseLast: FlagExclusivity {
    self.init(base: .chooseLast)
  }
}

extension Flag where Value == Optional<Bool> {
  /// Creates a Boolean property that reads its value from the presence of
  /// one or more inverted flags.
  ///
  /// Use this initializer to create an optional Boolean flag with an on/off
  /// pair. With the following declaration, for example, the user can specify
  /// either `--use-https` or `--no-use-https` to set the `useHTTPS` flag to
  /// `true` or `false`, respectively. If neither is specified, the resulting
  /// flag value would be `nil`.
  ///
  ///     @Flag(inversion: .prefixedNo)
  ///     var useHTTPS: Bool?
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - inversion: The method for converting this flags name into an on/off
  ///     pair.
  ///   - exclusivity: The behavior to use when an on/off pair of flags is
  ///     specified.
  ///   - help: Information about how to use this flag.
  public init(
    name: NameSpecification = .long,
    inversion: FlagInversion,
    exclusivity: FlagExclusivity = .chooseLast,
    help: ArgumentHelp? = nil
  ) {
    self.init(_parsedValue: .init { key in
      .flag(
        key: key,
        name: name,
        default: nil,
        required: false,
        inversion: inversion,
        exclusivity: exclusivity,
        help: help)
    })
  }

  /// This initializer allows a user to provide a `nil` default value for
  /// `@Flag`-marked `Optional<Bool>` property without allowing a non-`nil`
  /// default value.
  public init(
    wrappedValue _value: _OptionalNilComparisonType,
    name: NameSpecification = .long,
    inversion: FlagInversion,
    exclusivity: FlagExclusivity = .chooseLast,
    help: ArgumentHelp? = nil
  ) {
    self.init(
      name: name,
      inversion: inversion,
      exclusivity: exclusivity,
      help: help)
  }

}

extension Flag where Value == Bool {
  /// Creates a Boolean property with an optional default value, intended to be called by other constructors to centralize logic.
  ///
  /// This private `init` allows us to expose multiple other similar constructors to allow for standard default property initialization while reducing code duplication.
  private init(
    name: NameSpecification,
    initial: Bool?,
    help: ArgumentHelp? = nil
  ) {
    self.init(_parsedValue: .init { key in
      .flag(key: key, name: name, default: initial, help: help)
    })
  }

  /// Creates a Boolean property with default value provided by standard Swift default value syntax that reads its value from the presence of a flag.
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property, provided implicitly by the compiler during property wrapper initialization.
  ///   - name: A specification for what names are allowed for this flag.
  ///   - help: Information about how to use this flag.
  public init(
    wrappedValue: Bool,
    name: NameSpecification = .long,
    help: ArgumentHelp? = nil
  ) {
    self.init(
      name: name,
      initial: wrappedValue,
      help: help
    )
  }

  /// Creates a property with an optional default value, intended to be called by other constructors to centralize logic.
  ///
  /// This private `init` allows us to expose multiple other similar constructors to allow for standard default property initialization while reducing code duplication.
  private init(
    name: NameSpecification,
    initial: Bool?,
    inversion: FlagInversion,
    exclusivity: FlagExclusivity,
    help: ArgumentHelp?
  ) {
    self.init(_parsedValue: .init { key in
      .flag(
        key: key,
        name: name,
        default: initial,
        required: initial == nil,
        inversion: inversion,
        exclusivity: exclusivity,
        help: help)
      })
  }

  /// Creates a Boolean property with default value provided by standard Swift default value syntax that reads its value from the presence of one or more inverted flags.
  ///
  /// Use this initializer to create a Boolean flag with an on/off pair.
  /// With the following declaration, for example, the user can specify either `--use-https` or `--no-use-https` to set the `useHTTPS` flag to `true` or `false`, respectively.
  ///
  /// ```swift
  /// @Flag(inversion: .prefixedNo)
  /// var useHTTPS: Bool = true
  /// ````
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - wrappedValue: A default value to use for this property, provided implicitly by the compiler during property wrapper initialization.
  ///   - inversion: The method for converting this flag's name into an on/off pair.
  ///   - exclusivity: The behavior to use when an on/off pair of flags is specified.
  ///   - help: Information about how to use this flag.
  public init(
    wrappedValue: Bool,
    name: NameSpecification = .long,
    inversion: FlagInversion,
    exclusivity: FlagExclusivity = .chooseLast,
    help: ArgumentHelp? = nil
  ) {
    self.init(
      name: name,
      initial: wrappedValue,
      inversion: inversion,
      exclusivity: exclusivity,
      help: help
    )
  }

  /// Creates a Boolean property with no default value that reads its value from the presence of one or more inverted flags.
  ///
  /// Use this initializer to create a Boolean flag with an on/off pair.
  /// With the following declaration, for example, the user can specify either `--use-https` or `--no-use-https` to set the `useHTTPS` flag to `true` or `false`, respectively.
  ///
  /// ```swift
  /// @Flag(inversion: .prefixedNo)
  /// var useHTTPS: Bool
  /// ````
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - wrappedValue: A default value to use for this property, provided implicitly by the compiler during property wrapper initialization.
  ///   - inversion: The method for converting this flag's name into an on/off pair.
  ///   - exclusivity: The behavior to use when an on/off pair of flags is specified.
  ///   - help: Information about how to use this flag.
  public init(
    name: NameSpecification = .long,
    inversion: FlagInversion,
    exclusivity: FlagExclusivity = .chooseLast,
    help: ArgumentHelp? = nil
  ) {
    self.init(
      name: name,
      initial: nil,
      inversion: inversion,
      exclusivity: exclusivity,
      help: help
    )
  }
}

extension Flag where Value == Int {
  /// Creates an integer property that gets its value from the number of times
  /// a flag appears.
  ///
  /// This property defaults to a value of zero.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - help: Information about how to use this flag.
  public init(
    name: NameSpecification = .long,
    help: ArgumentHelp? = nil
  ) {
    self.init(_parsedValue: .init { key in
      .counter(key: key, name: name, help: help)
    })
  }
}

// - MARK: EnumerableFlag

extension Flag where Value: EnumerableFlag {
  /// Creates a property with an optional default value, intended to be called by other constructors to centralize logic.
  ///
  /// This private `init` allows us to expose multiple other similar constructors to allow for standard default property initialization while reducing code duplication.
  private init(
    initial: Value?,
    exclusivity: FlagExclusivity,
    help: ArgumentHelp?
  ) {
    self.init(_parsedValue: .init { key in
      // This gets flipped to `true` the first time one of these flags is
      // encountered.
      var hasUpdated = false

      // Create a string representation of the default value. Since this is a
      // flag, the default value to show to the user is the `--value-name`
      // flag that a user would provide on the command line, not a Swift value.
      let defaultValueFlag = initial.flatMap { value -> String? in
        let defaultKey = InputKey(name: String(describing: value), parent: key)
        let defaultNames = Value.name(for: value).makeNames(defaultKey)
        return defaultNames.first?.synopsisString
      }

      let caseHelps = Value.allCases.map { Value.help(for: $0) }
      let hasCustomCaseHelp = caseHelps.contains(where: { $0 != nil })

      let args = Value.allCases.enumerated().map { (i, value) -> ArgumentDefinition in
        let caseKey = InputKey(name: String(describing: value), parent: key)
        let name = Value.name(for: value)

        let helpForCase = caseHelps[i] ?? help
        var defaultValueString: String? = nil
        if hasCustomCaseHelp {
          if value == initial {
            defaultValueString = defaultValueFlag
          }
        } else {
          defaultValueString = defaultValueFlag
        }

        let help = ArgumentDefinition.Help(
          allValues: [],
          options: initial != nil ? .isOptional : [],
          help: helpForCase,
          defaultValue: defaultValueString,
          key: key,
          isComposite: !hasCustomCaseHelp)

        return ArgumentDefinition.flag(
          name: name,
          key: key,
          caseKey: caseKey,
          help: help,
          parsingStrategy: .default,
          initialValue: initial,
          update: .nullary({ (origin, name, values) in
            hasUpdated = try ArgumentSet.updateFlag(key: key, value: value, origin: origin, values: &values, hasUpdated: hasUpdated, exclusivity: exclusivity)
          })
        )
      }
      return ArgumentSet(args)
      })
  }

  /// Creates a property with a default value provided by standard Swift default value syntax that gets its value from the presence of a flag.
  ///
  /// Use this initializer to customize the name and number of states further than using a `Bool`.
  /// To use, define an `EnumerableFlag` enumeration with a case for each state, and use that as the type for your flag.
  /// In this case, the user can specify either `--use-production-server` or `--use-development-server` to set the flag's value.
  ///
  /// ```swift
  /// enum ServerChoice: EnumerableFlag {
  ///   case useProductionServer
  ///   case useDevelopmentServer
  /// }
  ///
  /// @Flag var serverChoice: ServerChoice = .useProductionServer
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property, provided implicitly by the compiler during property wrapper initialization.
  ///   - exclusivity: The behavior to use when multiple flags are specified.
  ///   - help: Information about how to use this flag.
  public init(
    wrappedValue: Value,
    exclusivity: FlagExclusivity = .exclusive,
    help: ArgumentHelp? = nil
  ) {
    self.init(
      initial: wrappedValue,
      exclusivity: exclusivity,
      help: help
    )
  }

  /// Creates a property with no default value that gets its value from the presence of a flag.
  ///
  /// Use this initializer to customize the name and number of states further than using a `Bool`.
  /// To use, define an `EnumerableFlag` enumeration with a case for each state, and use that as the type for your flag.
  /// In this case, the user can specify either `--use-production-server` or `--use-development-server` to set the flag's value.
  ///
  /// ```swift
  /// enum ServerChoice: EnumerableFlag {
  ///   case useProductionServer
  ///   case useDevelopmentServer
  /// }
  ///
  /// @Flag var serverChoice: ServerChoice
  /// ```
  ///
  /// - Parameters:
  ///   - exclusivity: The behavior to use when multiple flags are specified.
  ///   - help: Information about how to use this flag.
  public init(
    exclusivity: FlagExclusivity = .exclusive,
    help: ArgumentHelp? = nil
  ) {
    self.init(
      initial: nil,
      exclusivity: exclusivity,
      help: help
    )
  }
}

extension Flag {
  /// Creates a property that gets its value from the presence of a flag,
  /// where the allowed flags are defined by an `EnumerableFlag` type.
  public init<Element>(
    exclusivity: FlagExclusivity = .exclusive,
    help: ArgumentHelp? = nil
  ) where Value == Element?, Element: EnumerableFlag {
    self.init(_parsedValue: .init { parentKey in
      // This gets flipped to `true` the first time one of these flags is
      // encountered.
      var hasUpdated = false

      let caseHelps = Element.allCases.map { Element.help(for: $0) }
      let hasCustomCaseHelp = caseHelps.contains(where: { $0 != nil })

      let args = Element.allCases.enumerated().map { (i, value) -> ArgumentDefinition in
        let caseKey = InputKey(name: String(describing: value), parent: parentKey)
        let name = Element.name(for: value)
        let helpForCase = hasCustomCaseHelp ? (caseHelps[i] ?? help) : help

        let help = ArgumentDefinition.Help(
          allValues: [],
          options: [.isOptional],
          help: helpForCase,
          defaultValue: nil,
          key: parentKey,
          isComposite: !hasCustomCaseHelp)

        return ArgumentDefinition.flag(name: name, key: parentKey, caseKey: caseKey, help: help, parsingStrategy: .default, initialValue: nil as Element?, update: .nullary({ (origin, name, values) in
          hasUpdated = try ArgumentSet.updateFlag(key: parentKey, value: value, origin: origin, values: &values, hasUpdated: hasUpdated, exclusivity: exclusivity)
        }))

      }
      return ArgumentSet(args)
      })
  }

  /// Creates an array property with an optional default value, intended to be called by other constructors to centralize logic.
  ///
  /// This private `init` allows us to expose multiple other similar constructors to allow for standard default property initialization while reducing code duplication.
  private init<Element>(
    initial: [Element]?,
    help: ArgumentHelp? = nil
  ) where Value == Array<Element>, Element: EnumerableFlag {
    self.init(_parsedValue: .init { parentKey in
      let caseHelps = Element.allCases.map { Element.help(for: $0) }
      let hasCustomCaseHelp = caseHelps.contains(where: { $0 != nil })

      let args = Element.allCases.enumerated().map { (i, value) -> ArgumentDefinition in
        let caseKey = InputKey(name: String(describing: value), parent: parentKey)
        let name = Element.name(for: value)
        let helpForCase = hasCustomCaseHelp ? (caseHelps[i] ?? help) : help
        let help = ArgumentDefinition.Help(
          allValues: [],
          options: [.isOptional],
          help: helpForCase,
          defaultValue: nil,
          key: parentKey,
          isComposite: !hasCustomCaseHelp)

        return ArgumentDefinition.flag(name: name, key: parentKey, caseKey: caseKey, help: help, parsingStrategy: .default, initialValue: initial, update: .nullary({ (origin, name, values) in
          values.update(forKey: parentKey, inputOrigin: origin, initial: [Element](), closure: {
            $0.append(value)
          })
        }))
      }
      return ArgumentSet(args)
    })
  }

  /// Creates an array property that gets its values from the presence of
  /// zero or more flags, where the allowed flags are defined by an
  /// `EnumerableFlag` type.
  ///
  /// This property has an empty array as its default value.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - help: Information about how to use this flag.
  public init<Element>(
    wrappedValue: [Element],
    help: ArgumentHelp? = nil
  ) where Value == Array<Element>, Element: EnumerableFlag {
    self.init(
      initial: wrappedValue,
      help: help
    )
  }

  /// Creates an array property with no default value that gets its values from the presence of zero or more flags, where the allowed flags are defined by an `EnumerableFlag` type.
  ///
  /// This method is called to initialize an array `Flag` with no default value such as:
  /// ```swift
  /// @Flag
  /// var foo: [CustomFlagType]
  /// ```
  ///
  /// - Parameters:
  ///   - help: Information about how to use this flag.
  public init<Element>(
    help: ArgumentHelp? = nil
  ) where Value == Array<Element>, Element: EnumerableFlag {
    self.init(
      initial: nil,
      help: help
    )
  }
}

extension ArgumentDefinition {
  static func flag<V>(name: NameSpecification, key: InputKey, caseKey: InputKey, help: Help, parsingStrategy: ArgumentDefinition.ParsingStrategy, initialValue: V?, update: Update) -> ArgumentDefinition {
    return ArgumentDefinition(kind: .name(key: caseKey, specification: name), help: help, completion: .default, parsingStrategy: parsingStrategy, update: update, initial: { origin, values in
      if let initial = initialValue {
        values.set(initial, forKey: key, inputOrigin: origin)
      }
    })
  }
}

/// A specification for how to represent a property as a command-line argument
/// label.
public struct NameSpecification: ExpressibleByArrayLiteral {
  /// An individual property name translation.
  public struct Element: Hashable {
    internal enum Representation: Hashable {
      case long
      case customLong(_ name: String, withSingleDash: Bool)
      case short
      case customShort(_ char: Character, allowingJoined: Bool)
    }

    internal var base: Representation

    /// Use the property's name, converted to lowercase with words separated by
    /// hyphens.
    ///
    /// For example, a property named `allowLongNames` would be converted to the
    /// label `--allow-long-names`.
    public static var long: Element {
      self.init(base: .long)
    }

    /// Use the given string instead of the property's name.
    ///
    /// To create a single-dash argument, pass `true` as `withSingleDash`. Note
    /// that combining single-dash options and options with short,
    /// single-character names can lead to ambiguities for the user.
    ///
    /// - Parameters:
    ///   - name: The name of the option or flag.
    ///   - withSingleDash: A Boolean value indicating whether to use a single
    ///     dash as the prefix. If `false`, the name has a double-dash prefix.
    public static func customLong(_ name: String, withSingleDash: Bool = false) -> Element {
      self.init(base: .customLong(name, withSingleDash: withSingleDash))
    }

    /// Use the first character of the property's name as a short option label.
    ///
    /// For example, a property named `verbose` would be converted to the
    /// label `-v`. Short labels can be combined into groups.
    public static var short: Element {
      self.init(base: .short)
    }

    /// Use the given character as a short option label.
    ///
    /// When passing `true` as `allowingJoined` in an `@Option` declaration,
    /// the user can join a value with the option name. For example, if an
    /// option is declared as `-D`, allowing joined values, a user could pass
    /// `-Ddebug` to specify `debug` as the value for that option.
    ///
    /// - Parameters:
    ///   - char: The name of the option or flag.
    ///   - allowingJoined: A Boolean value indicating whether this short name
    ///     allows a joined value.
    public static func customShort(_ char: Character, allowingJoined: Bool = false) -> Element {
      self.init(base: .customShort(char, allowingJoined: allowingJoined))
    }
  }
  var elements: [Element]

  public init<S>(_ sequence: S) where S : Sequence, Element == S.Element {
    self.elements = sequence.uniquing()
  }

  public init(arrayLiteral elements: Element...) {
    self.init(elements)
  }
}

extension NameSpecification {
  /// Use the property's name converted to lowercase with words separated by
  /// hyphens.
  ///
  /// For example, a property named `allowLongNames` would be converted to the
  /// label `--allow-long-names`.
  public static var long: NameSpecification { [.long] }

  /// Use the given string instead of the property's name.
  ///
  /// To create a single-dash argument, pass `true` as `withSingleDash`. Note
  /// that combining single-dash options and options with short,
  /// single-character names can lead to ambiguities for the user.
  ///
  /// - Parameters:
  ///   - name: The name of the option or flag.
  ///   - withSingleDash: A Boolean value indicating whether to use a single
  ///     dash as the prefix. If `false`, the name has a double-dash prefix.
  public static func customLong(_ name: String, withSingleDash: Bool = false) -> NameSpecification {
    [.customLong(name, withSingleDash: withSingleDash)]
  }

  /// Use the first character of the property's name as a short option label.
  ///
  /// For example, a property named `verbose` would be converted to the
  /// label `-v`. Short labels can be combined into groups.
  public static var short: NameSpecification { [.short] }

  /// Use the given character as a short option label.
  ///
  /// When passing `true` as `allowingJoined` in an `@Option` declaration,
  /// the user can join a value with the option name. For example, if an
  /// option is declared as `-D`, allowing joined values, a user could pass
  /// `-Ddebug` to specify `debug` as the value for that option.
  ///
  /// - Parameters:
  ///   - char: The name of the option or flag.
  ///   - allowingJoined: A Boolean value indicating whether this short name
  ///     allows a joined value.
  public static func customShort(_ char: Character, allowingJoined: Bool = false) -> NameSpecification {
    [.customShort(char, allowingJoined: allowingJoined)]
  }

  /// Combine the `.short` and `.long` specifications to allow both long
  /// and short labels.
  ///
  /// For example, a property named `verbose` would be converted to both the
  /// long `--verbose` and short `-v` labels.
  public static var shortAndLong: NameSpecification { [.long, .short] }
}

extension NameSpecification.Element {
  /// Creates the argument name for this specification element.
  internal func name(for key: InputKey) -> Name? {
    switch self.base {
    case .long:
      return .long(key.name.convertedToSnakeCase(separator: "-"))
    case .short:
      guard let c = key.name.first else { fatalError("Key '\(key.name)' has not characters to form short option name.") }
      return .short(c)
    case .customLong(let name, let withSingleDash):
      return withSingleDash
        ? .longWithSingleDash(name)
        : .long(name)
    case .customShort(let name, let allowingJoined):
      return .short(name, allowingJoined: allowingJoined)
    }
  }
}

extension NameSpecification {
  /// Creates the argument names for each element in the name specification.
  internal func makeNames(_ key: InputKey) -> [Name] {
    return elements.compactMap { $0.name(for: key) }
  }
}

extension FlagInversion {
  /// Creates the enable and disable name(s) for the given flag.
  internal func enableDisableNamePair(for key: InputKey, name: NameSpecification) -> ([Name], [Name]) {

    func makeNames(withPrefix prefix: String, includingShort: Bool) -> [Name] {
      return name.elements.compactMap { element -> Name? in
        switch element.base {
        case .short, .customShort:
          return includingShort ? element.name(for: key) : nil
        case .long:
          let modifiedKey = InputKey(name: key.name.addingIntercappedPrefix(prefix), parent: key)
          return element.name(for: modifiedKey)
        case .customLong(let name, let withSingleDash):
          let modifiedName = name.addingPrefixWithAutodetectedStyle(prefix)
          let modifiedElement = NameSpecification.Element.customLong(modifiedName, withSingleDash: withSingleDash)
          return modifiedElement.name(for: key)
        }
      }
    }

    switch self.base {
    case .prefixedNo:
      return (
        name.makeNames(key),
        makeNames(withPrefix: "no", includingShort: false)
      )
    case .prefixedEnableDisable:
      return (
        makeNames(withPrefix: "enable", includingShort: true),
        makeNames(withPrefix: "disable", includingShort: false)
      )
    }
  }
}

/// A property wrapper that represents a command-line option.
///
/// Use the `@Option` wrapper to define a property of your custom command as a
/// command-line option. An *option* is a named value passed to a command-line
/// tool, like `--configuration debug`. Options can be specified in any order.
///
/// An option can have a default value specified as part of its
/// declaration; options with optional `Value` types implicitly have `nil` as
/// their default value. Options that are neither declared as `Optional` nor
/// given a default value are required for users of your command-line tool.
///
/// For example, the following program defines three options:
///
///     @main
///     struct Greet: ParsableCommand {
///         @Option var greeting = "Hello"
///         @Option var age: Int? = nil
///         @Option var name: String
///
///         mutating func run() {
///             print("\(greeting) \(name)!")
///             if let age = age {
///                 print("Congrats on making it to the ripe old age of \(age)!")
///             }
///         }
///     }
///
/// `greeting` has a default value of `"Hello"`, which can be overridden by
/// providing a different string as an argument, while `age` defaults to `nil`.
/// `name` is a required option because it is non-`nil` and has no default
/// value.
///
///     $ greet --name Alicia
///     Hello Alicia!
///     $ greet --age 28 --name Seungchin --greeting Hi
///     Hi Seungchin!
///     Congrats on making it to the ripe old age of 28!
@propertyWrapper
public struct Option<Value>: Decodable, ParsedWrapper {
  internal var _parsedValue: Parsed<Value>

  internal init(_parsedValue: Parsed<Value>) {
    self._parsedValue = _parsedValue
  }

  public init(from decoder: Decoder) throws {
    try self.init(_decoder: decoder)
  }

  /// This initializer works around a quirk of property wrappers, where the
  /// compiler will not see no-argument initializers in extensions. Explicitly
  /// marking this initializer unavailable means that when `Value` conforms to
  /// `ExpressibleByArgument`, that overload will be selected instead.
  ///
  /// ```swift
  /// @Option() var foo: String // Syntax without this initializer
  /// @Option var foo: String   // Syntax with this initializer
  /// ```
  @available(*, unavailable, message: "A default value must be provided unless the value type conforms to ExpressibleByArgument.")
  public init() {
    fatalError("unavailable")
  }

  /// The value presented by this property wrapper.
  public var wrappedValue: Value {
    get {
      switch _parsedValue {
      case .value(let v):
        return v
      case .definition:
        fatalError(directlyInitializedError)
      }
    }
    set {
      _parsedValue = .value(newValue)
    }
  }
}

extension Option: CustomStringConvertible {
  public var description: String {
    switch _parsedValue {
    case .value(let v):
      return String(describing: v)
    case .definition:
      return "Option(*definition*)"
    }
  }
}

extension Option: DecodableParsedWrapper where Value: Decodable {}

/// The strategy to use when parsing a single value from `@Option` arguments.
///
/// - SeeAlso: ``ArrayParsingStrategy``
public struct SingleValueParsingStrategy: Hashable {
  internal var base: ArgumentDefinition.ParsingStrategy

  /// Parse the input after the option. Expect it to be a value.
  ///
  /// For inputs such as `--foo foo`, this would parse `foo` as the
  /// value. However, the input `--foo --bar foo bar` would
  /// result in an error. Even though two values are provided, they don’t
  /// succeed each option. Parsing would result in an error such as the following:
  ///
  ///     Error: Missing value for '--foo <foo>'
  ///     Usage: command [--foo <foo>]
  ///
  /// This is the **default behavior** for `@Option`-wrapped properties.
  public static var next: SingleValueParsingStrategy {
    self.init(base: .default)
  }

  /// Parse the next input, even if it could be interpreted as an option or
  /// flag.
  ///
  /// For inputs such as `--foo --bar baz`, if `.unconditional` is used for `foo`,
  /// this would read `--bar` as the value for `foo` and would use `baz` as
  /// the next positional argument.
  ///
  /// This allows reading negative numeric values or capturing flags to be
  /// passed through to another program since the leading hyphen is normally
  /// interpreted as the start of another option.
  ///
  /// - Note: This is usually *not* what users would expect. Use with caution.
  public static var unconditional: SingleValueParsingStrategy {
    self.init(base: .unconditional)
  }

  /// Parse the next input, as long as that input can't be interpreted as
  /// an option or flag.
  ///
  /// - Note: This will skip other options and _read ahead_ in the input
  /// to find the next available value. This may be *unexpected* for users.
  /// Use with caution.
  ///
  /// For example, if `--foo` takes a value, then the input `--foo --bar bar`
  /// would be parsed such that the value `bar` is used for `--foo`.
  public static var scanningForValue: SingleValueParsingStrategy {
    self.init(base: .scanningForValue)
  }
}

/// The strategy to use when parsing multiple values from `@Option` arguments into an
/// array.
public struct ArrayParsingStrategy: Hashable {
  internal var base: ArgumentDefinition.ParsingStrategy

  /// Parse one value per option, joining multiple into an array.
  ///
  /// For example, for a parsable type with a property defined as
  /// `@Option(parsing: .singleValue) var read: [String]`,
  /// the input `--read foo --read bar` would result in the array
  /// `["foo", "bar"]`. The same would be true for the input
  /// `--read=foo --read=bar`.
  ///
  /// - Note: This follows the default behavior of differentiating between values and options. As
  ///     such, the value for this option will be the next value (non-option) in the input. For the
  ///     above example, the input `--read --name Foo Bar` would parse `Foo` into
  ///     `read` (and `Bar` into `name`).
  public static var singleValue: ArrayParsingStrategy {
    self.init(base: .default)
  }

  /// Parse the value immediately after the option while allowing repeating options, joining multiple into an array.
  ///
  /// This is identical to `.singleValue` except that the value will be read
  /// from the input immediately after the option, even if it could be interpreted as an option.
  ///
  /// For example, for a parsable type with a property defined as
  /// `@Option(parsing: .unconditionalSingleValue) var read: [String]`,
  /// the input `--read foo --read bar` would result in the array
  /// `["foo", "bar"]` -- just as it would have been the case for `.singleValue`.
  ///
  /// - Note: However, the input `--read --name Foo Bar --read baz` would result in
  /// `read` being set to the array `["--name", "baz"]`. This is usually *not* what users
  /// would expect. Use with caution.
  public static var unconditionalSingleValue: ArrayParsingStrategy {
    self.init(base: .unconditional)
  }

  /// Parse all values up to the next option.
  ///
  /// For example, for a parsable type with a property defined as
  /// `@Option(parsing: .upToNextOption) var files: [String]`,
  /// the input `--files foo bar` would result in the array
  /// `["foo", "bar"]`.
  ///
  /// Parsing stops as soon as there’s another option in the input such that
  /// `--files foo bar --verbose` would also set `files` to the array
  /// `["foo", "bar"]`.
  public static var upToNextOption: ArrayParsingStrategy {
    self.init(base: .upToNextOption)
  }

  /// Parse all remaining arguments into an array.
  ///
  /// `.remaining` can be used for capturing pass-through flags. For example, for
  /// a parsable type defined as
  /// `@Option(parsing: .remaining) var passthrough: [String]`:
  ///
  ///     $ cmd --passthrough --foo 1 --bar 2 -xvf
  ///     ------------
  ///     options.passthrough == ["--foo", "1", "--bar", "2", "-xvf"]
  ///
  /// - Note: This will read all inputs following the option without attempting to do any parsing. This is
  /// usually *not* what users would expect. Use with caution.
  ///
  /// Consider using a trailing `@Argument` instead and letting users explicitly turn off parsing
  /// through the terminator `--`. That is the more common approach. For example:
  /// ```swift
  /// struct Options: ParsableArguments {
  ///     @Option var name: String
  ///     @Argument var remainder: [String]
  /// }
  /// ```
  /// would parse the input `--name Foo -- Bar --baz` such that the `remainder`
  /// would hold the value `["Bar", "--baz"]`.
  public static var remaining: ArrayParsingStrategy {
    self.init(base: .allRemainingInput)
  }
}

// MARK: - @Option T: ExpressibleByArgument Initializers
extension Option where Value: ExpressibleByArgument {
  /// Creates a property with a default value provided by standard Swift default value syntax.
  ///
  /// This method is called to initialize an `Option` with a default value such as:
  /// ```swift
  /// @Option var foo: String = "bar"
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property, provided
  ///   implicitly by the compiler during property wrapper initialization.
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  public init(
    wrappedValue: Value,
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  @available(*, deprecated, message: """
    Swap the order of the 'help' and 'completion' arguments.
    """)
  public init(
    wrappedValue: Value,
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    completion: CompletionKind?,
    help: ArgumentHelp?
  ) {
    self.init(
      wrappedValue: wrappedValue,
      name: name,
      parsing: parsingStrategy,
      help: help,
      completion: completion)
  }

  /// Creates a property with no default value.
  ///
  /// This method is called to initialize an `Option` without a default value such as:
  /// ```swift
  /// @Option var foo: String
  /// ```
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  public init(
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Option T Initializers
extension Option {
  /// Creates a property with a default value provided by standard Swift default value syntax.
  ///
  /// This method is called to initialize an `Option` with a default value such as:
  /// ```swift
  /// @Option var foo: String = "bar"
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property, provided
  ///   implicitly by the compiler during property wrapper initialization.
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init(
    wrappedValue: Value,
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> Value
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates a property with no default value.
  ///
  /// This method is called to initialize an `Option` without a default value such as:
  /// ```swift
  /// @Option var foo: String
  /// ```
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  public init(
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> Value
  ) {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Bare<Value>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Option Optional<T: ExpressibleByArgument> Initializers
extension Option {
  /// This initializer allows a user to provide a `nil` default value for an
  /// optional `@Option`-marked property without allowing a non-`nil` default
  /// value.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's
  ///     value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    wrappedValue _value: _OptionalNilComparisonType,
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  @available(*, deprecated, message: """
    Optional @Options with default values should be declared as non-Optional.
    """)
  @_disfavoredOverload
  public init<T>(
    wrappedValue: Optional<T>,
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates a property that reads its value from a labeled option.
  ///
  /// If the property has an `Optional` type, or you provide a non-`nil`
  /// value for the `initial` parameter, specifying this option is not
  /// required.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's
  ///     value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Option Optional<T> Initializers
extension Option {
  /// Creates a property with a default value provided by standard Swift default
  /// value syntax, parsing with the given closure.
  ///
  /// This method is called to initialize an `Option` with a default value such as:
  /// ```swift
  /// @Option(transform: baz)
  /// var foo: String = "bar"
  /// ```
  ///
  /// - Parameters:
  ///   - wrappedValue: A default value to use for this property, provided
  ///   implicitly by the compiler during property wrapper initialization.
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's type
  ///   or throws an error.
  public init<T>(
    wrappedValue _value: _OptionalNilComparisonType,
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  @available(*, deprecated, message: """
    Optional @Options with default values should be declared as non-Optional.
    """)
  @_disfavoredOverload
  public init<T>(
    wrappedValue: Optional<T>,
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates a property with no default value, parsing with the given closure.
  ///
  /// This method is called to initialize an `Option` with no default value such as:
  /// ```swift
  /// @Option(transform: baz)
  /// var foo: String
  /// ```
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when looking for this option's value.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's type or throws an error.
  public init<T>(
    name: NameSpecification = .long,
    parsing parsingStrategy: SingleValueParsingStrategy = .next,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Optional<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Optional<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Option Array<T: ExpressibleByArgument> Initializers
extension Option {
  /// Creates an array property that reads its values from zero or more
  /// labeled options.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - initial: A default value to use for this property.
  ///   - parsingStrategy: The behavior to use when parsing multiple values
  ///     from the command-line arguments.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    wrappedValue: Array<T>,
    name: NameSpecification = .long,
    parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates an array property with no default value that reads its values from zero or more labeled options.
  ///
  /// This method is called to initialize an array `Option` with no default value such as:
  /// ```swift
  /// @Option()
  /// var foo: [String]
  /// ```
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when parsing multiple values from the command-line arguments.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  public init<T>(
    name: NameSpecification = .long,
    parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil
  ) where T: ExpressibleByArgument, Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

// MARK: - @Option Array<T> Initializers
extension Option {
  /// Creates an array property that reads its values from zero or more
  /// labeled options, parsing with the given closure.
  ///
  /// This property defaults to an empty array if the `initial` parameter
  /// is not specified.
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - initial: A default value to use for this property. If `initial` is
  ///     `nil`, this option defaults to an empty array.
  ///   - parsingStrategy: The behavior to use when parsing multiple values
  ///     from the command-line arguments.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///     element type or throws an error.
  public init<T>(
    wrappedValue: Array<T>,
    name: NameSpecification = .long,
    parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: wrappedValue,
        completion: completion)

      return ArgumentSet(arg)
    })
  }

  /// Creates an array property with no default value that reads its values from
  /// zero or more labeled options, parsing each element with the given closure.
  ///
  /// This method is called to initialize an array `Option` with no default value such as:
  /// ```swift
  /// @Option(transform: baz)
  /// var foo: [String]
  /// ```
  ///
  /// - Parameters:
  ///   - name: A specification for what names are allowed for this flag.
  ///   - parsingStrategy: The behavior to use when parsing multiple values from
  ///   the command-line arguments.
  ///   - help: Information about how to use this option.
  ///   - completion: Kind of completion provided to the user for this option.
  ///   - transform: A closure that converts a string into this property's
  ///   element type or throws an error.
  public init<T>(
    name: NameSpecification = .long,
    parsing parsingStrategy: ArrayParsingStrategy = .singleValue,
    help: ArgumentHelp? = nil,
    completion: CompletionKind? = nil,
    transform: @escaping (String) throws -> T
  ) where Value == Array<T> {
    self.init(_parsedValue: .init { key in
      let arg = ArgumentDefinition(
        container: Array<T>.self,
        key: key,
        kind: .name(key: key, specification: name),
        help: help,
        parsingStrategy: parsingStrategy.base,
        transform: transform,
        initial: nil,
        completion: completion)

      return ArgumentSet(arg)
    })
  }
}

/// A wrapper that transparently includes a parsable type.
///
/// Use an option group to include a group of options, flags, or arguments
/// declared in a parsable type.
///
///     struct GlobalOptions: ParsableArguments {
///         @Flag(name: .shortAndLong)
///         var verbose: Bool
///
///         @Argument var values: [Int]
///     }
///
///     struct Options: ParsableArguments {
///         @Option var name: String
///         @OptionGroup var globals: GlobalOptions
///     }
///
/// The flag and positional arguments declared as part of `GlobalOptions` are
/// included when parsing `Options`.
@propertyWrapper
public struct OptionGroup<Value: ParsableArguments>: Decodable, ParsedWrapper {
  internal var _parsedValue: Parsed<Value>
  internal var _visibility: ArgumentVisibility

  // FIXME: Adding this property works around the crasher described in
  // https://github.com/apple/swift-argument-parser/issues/338
  internal var _dummy: Bool = false

  /// The title to use in the help screen for this option group.
  public var title: String = ""

  internal init(_parsedValue: Parsed<Value>) {
    self._parsedValue = _parsedValue
    self._visibility = .default
  }

  public init(from decoder: Decoder) throws {
    if let d = decoder as? SingleValueDecoder,
      let value = try? d.previousValue(Value.self)
    {
      self.init(_parsedValue: .value(value))
    } else {
      try self.init(_decoder: decoder)
      if let d = decoder as? SingleValueDecoder {
        d.saveValue(wrappedValue)
      }
    }

    do {
      try wrappedValue.validate()
    } catch {
      throw ParserError.userValidationError(error)
    }
  }

  /// Creates a property that represents another parsable type, using the
  /// specified title and visibility.
  ///
  /// - Parameters:
  ///   - title: A title for grouping this option group's members in your
  ///     command's help screen. If `title` is empty, the members will be
  ///     displayed alongside the other arguments, flags, and options declared
  ///     by your command.
  ///   - visibility: The visibility to use for the entire option group.
  public init(
    title: String = "",
    visibility: ArgumentVisibility = .default
  ) {
    self.init(_parsedValue: .init { parentKey in
      var args = ArgumentSet(Value.self, visibility: .private, parent: parentKey)
      args.content.withEach {
        $0.help.parentTitle = title
      }
      return args
    })
    self._visibility = visibility
    self.title = title
  }

  /// The value presented by this property wrapper.
  public var wrappedValue: Value {
    get {
      switch _parsedValue {
      case .value(let v):
        return v
      case .definition:
        fatalError(directlyInitializedError)
      }
    }
    set {
      _parsedValue = .value(newValue)
    }
  }
}

extension OptionGroup: CustomStringConvertible {
  public var description: String {
    switch _parsedValue {
    case .value(let v):
      return String(describing: v)
    case .definition:
      return "OptionGroup(*definition*)"
    }
  }
}

// Experimental use with caution
extension OptionGroup {
  @available(*, deprecated, renamed: "init(visibility:)")
  public init(_hiddenFromHelp: Bool) {
    self.init(visibility: .hidden)
  }

  /// Creates a property that represents another parsable type.
  @available(*, deprecated, renamed: "init(visibility:)")
  @_disfavoredOverload
  public init() {
    self.init(visibility: .default)
  }
}

// MARK: Deprecated

extension OptionGroup {
  @_disfavoredOverload
  @available(*, deprecated, renamed: "init(title:visibility:)")
  public init(
    visibility _visibility: ArgumentVisibility = .default
  ) {
    self.init(title: "", visibility: _visibility)
  }
}


// MARK: Parsable Types


/// A type that can be executed as part of a nested tree of commands.
public protocol ParsableCommand: ParsableArguments {
  /// Configuration for this command, including subcommands and custom help
  /// text.
  static var configuration: CommandConfiguration { get }

  /// *For internal use only:* The name for the command on the command line.
  ///
  /// This is generated from the configuration, if given, or from the type
  /// name if not. This is a customization point so that a WrappedParsable
  /// can pass through the wrapped type's name.
  static var _commandName: String { get }

  /// The behavior or functionality of this command.
  ///
  /// Implement this method in your `ParsableCommand`-conforming type with the
  /// functionality that this command represents.
  ///
  /// This method has a default implementation that prints the help screen for
  /// this command.
  mutating func run() throws
}

// MARK: - Default implementations

extension ParsableCommand {
  public static var _commandName: String {
    configuration.commandName ??
      String(describing: Self.self).convertedToSnakeCase(separator: "-")
  }

  public static var configuration: CommandConfiguration {
    CommandConfiguration()
  }

  public mutating func run() throws {
    throw CleanExit.helpRequest(self)
  }
}

// MARK: - API

extension ParsableCommand {
  /// Parses an instance of this type, or one of its subcommands, from
  /// command-line arguments.
  ///
  /// - Parameter arguments: An array of arguments to use for parsing. If
  ///   `arguments` is `nil`, this uses the program's command-line arguments.
  /// - Returns: A new instance of this type, one of its subcommands, or a
  ///   command type internal to the `ArgumentParser` library.
  public static func parseAsRoot(
    _ arguments: [String]? = nil
  ) throws -> ParsableCommand {
    var parser = CommandParser(self)
    let arguments = arguments ?? Array(CommandLine.arguments.dropFirst())
    return try parser.parse(arguments: arguments).get()
  }

  /// Returns the text of the help screen for the given subcommand of this
  /// command.
  ///
  /// - Parameters:
  ///   - subcommand: The subcommand to generate the help screen for.
  ///     `subcommand` must be declared in the subcommand tree of this
  ///     command.
  ///   - columns: The column width to use when wrapping long line in the
  ///     help screen. If `columns` is `nil`, uses the current terminal
  ///     width, or a default value of `80` if the terminal width is not
  ///     available.
  /// - Returns: The full help screen for this type.
  @_disfavoredOverload
  @available(*, deprecated, renamed: "helpMessage(for:includeHidden:columns:)")
  public static func helpMessage(
    for _subcommand: ParsableCommand.Type,
    columns: Int? = nil
  ) -> String {
    helpMessage(for: _subcommand, includeHidden: false, columns: columns)
  }

  /// Returns the text of the help screen for the given subcommand of this
  /// command.
  ///
  /// - Parameters:
  ///   - subcommand: The subcommand to generate the help screen for.
  ///     `subcommand` must be declared in the subcommand tree of this
  ///     command.
  ///   - includeHidden: Include hidden help information in the generated
  ///     message.
  ///   - columns: The column width to use when wrapping long line in the
  ///     help screen. If `columns` is `nil`, uses the current terminal
  ///     width, or a default value of `80` if the terminal width is not
  ///     available.
  /// - Returns: The full help screen for this type.
  public static func helpMessage(
    for subcommand: ParsableCommand.Type,
    includeHidden: Bool = false,
    columns: Int? = nil
  ) -> String {
    HelpGenerator(
      commandStack: CommandParser(self).commandStack(for: subcommand),
      visibility: includeHidden ? .hidden : .default)
        .rendered(screenWidth: columns)
  }

  /// Executes this command, or one of its subcommands, with the given
  /// arguments.
  ///
  /// This method parses an instance of this type, one of its subcommands, or
  /// another built-in `ParsableCommand` type, from command-line arguments,
  /// and then calls its `run()` method, exiting with a relevant error message
  /// if necessary.
  ///
  /// - Parameter arguments: An array of arguments to use for parsing. If
  ///   `arguments` is `nil`, this uses the program's command-line arguments.
  public static func main(_ arguments: [String]?) {

#if DEBUG
    if #available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *) {
      if let asyncCommand = firstAsyncSubcommand(self) {
        if Self() is AsyncParsableCommand {
          failAsyncPlatform(rootCommand: self)
        } else {
          failAsyncHierarchy(rootCommand: self, subCommand: asyncCommand)
        }
      }
    }
#endif

    do {
      var command = try parseAsRoot(arguments)
      try command.run()
    } catch {
      exit(withError: error)
    }
  }

  /// Executes this command, or one of its subcommands, with the program's
  /// command-line arguments.
  ///
  /// Instead of calling this method directly, you can add `@main` to the root
  /// command for your command-line tool.
  ///
  /// This method parses an instance of this type, one of its subcommands, or
  /// another built-in `ParsableCommand` type, from command-line arguments,
  /// and then calls its `run()` method, exiting with a relevant error message
  /// if necessary.
  public static func main() {
    self.main(nil)
  }
}

// MARK: - Internal API

extension ParsableCommand {
  /// `true` if this command contains any array arguments that are declared
  /// with `.unconditionalRemaining`.
  internal static var includesPassthroughArguments: Bool {
    ArgumentSet(self, visibility: .private, parent: nil).contains(where: {
      $0.isRepeatingPositional && $0.parsingStrategy == .allRemainingInput
    })
  }

  internal static var includesAllUnrecognizedArgument: Bool {
    ArgumentSet(self, visibility: .private, parent: nil).contains(where: {
      $0.isRepeatingPositional && $0.parsingStrategy == .allUnrecognized
    })
  }

  /// `true` if this command's default subcommand contains any array arguments
  /// that are declared with `.unconditionalRemaining`. This is `false` if
  /// there's no default subcommand.
  internal static var defaultIncludesPassthroughArguments: Bool {
    configuration.defaultSubcommand?.includesPassthroughArguments == true
  }

#if DEBUG
  @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
  internal static func checkAsyncHierarchy(_ command: ParsableCommand.Type, root: String) {
    for sub in command.configuration.subcommands {
      checkAsyncHierarchy(sub, root: root)

      guard sub.configuration.subcommands.isEmpty else { continue }
      guard sub is AsyncParsableCommand.Type else { continue }

      fatalError("""

      --------------------------------------------------------------------
      Asynchronous subcommand of a synchronous root.

      The asynchronous command `\(sub)` is declared as a subcommand of the synchronous root command `\(root)`.

      With this configuration, your asynchronous `run()` method will not be called. To fix this issue, change `\(root)`'s `ParsableCommand` conformance to `AsyncParsableCommand`.
      --------------------------------------------------------------------

      """.wrapped(to: 70))
    }
  }

  @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
  internal static func firstAsyncSubcommand(_ command: ParsableCommand.Type) -> AsyncParsableCommand.Type? {
    for sub in command.configuration.subcommands {
      if let asyncCommand = sub as? AsyncParsableCommand.Type,
         sub.configuration.subcommands.isEmpty
      {
        return asyncCommand
      }

      if let asyncCommand = firstAsyncSubcommand(sub) {
        return asyncCommand
      }
    }

    return nil
  }
#endif
}

// MARK: Async Configuration Errors

func failAsyncHierarchy(
  rootCommand: ParsableCommand.Type, subCommand: ParsableCommand.Type
) -> Never {
  fatalError("""

  --------------------------------------------------------------------
  Asynchronous subcommand of a synchronous root.

  The asynchronous command `\(subCommand)` is declared as a subcommand of the synchronous root command `\(rootCommand)`.

  With this configuration, your asynchronous `run()` method will not be called. To fix this issue, change `\(rootCommand)`'s `ParsableCommand` conformance to `AsyncParsableCommand`.
  --------------------------------------------------------------------

  """.wrapped(to: 70))
}

func failAsyncPlatform(rootCommand: ParsableCommand.Type) -> Never {
  fatalError("""

  --------------------------------------------------------------------
  Asynchronous root command needs availability annotation.

  The asynchronous root command `\(rootCommand)` needs an availability annotation in order to be executed asynchronously. To fix this issue, add the following availability attribute to your `\(rootCommand)` declaration or set the minimum platform in your "Package.swift" file.

  """.wrapped(to: 70)
  + """

  @available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
  --------------------------------------------------------------------

  """)
}

fileprivate protocol ParsableArgumentsValidator {
  static func validate(_ type: ParsableArguments.Type, parent: InputKey?) -> ParsableArgumentsValidatorError?
}

enum ValidatorErrorKind {
  case warning
  case failure
}

protocol ParsableArgumentsValidatorError: Error {
  var kind: ValidatorErrorKind { get }
}

struct ParsableArgumentsValidationError: Error, CustomStringConvertible {
  let parsableArgumentsType: ParsableArguments.Type
  let underlayingErrors: [Error]
  var description: String {
    """
    Validation failed for `\(parsableArgumentsType)`:

    \(underlayingErrors.map({"- \($0)"}).joined(separator: "\n"))


    """
  }
}

extension ParsableArguments {
  static func _validate(parent: InputKey?) throws {
    let validators: [ParsableArgumentsValidator.Type] = [
      PositionalArgumentsValidator.self,
      ParsableArgumentsCodingKeyValidator.self,
      ParsableArgumentsUniqueNamesValidator.self,
      NonsenseFlagsValidator.self,
    ]
    let errors = validators.compactMap { validator in
      validator.validate(self, parent: parent)
    }
    if errors.count > 0 {
      throw ParsableArgumentsValidationError(parsableArgumentsType: self, underlayingErrors: errors)
    }
  }
}

fileprivate extension ArgumentSet {
  var firstPositionalArgument: ArgumentDefinition? {
    content.first(where: { $0.isPositional })
  }

  var firstRepeatedPositionalArgument: ArgumentDefinition? {
    content.first(where: { $0.isRepeatingPositional })
  }
}

/// For positional arguments to be valid, there must be at most one
/// positional array argument, and it must be the last positional argument
/// in the argument list. Any other configuration leads to ambiguity in
/// parsing the arguments.
struct PositionalArgumentsValidator: ParsableArgumentsValidator {
  struct Error: ParsableArgumentsValidatorError, CustomStringConvertible {
    let repeatedPositionalArgument: String

    let positionalArgumentFollowingRepeated: String

    var description: String {
      "Can't have a positional argument `\(positionalArgumentFollowingRepeated)` following an array of positional arguments `\(repeatedPositionalArgument)`."
    }

    var kind: ValidatorErrorKind { .failure }
  }

  static func validate(_ type: ParsableArguments.Type, parent: InputKey?) -> ParsableArgumentsValidatorError? {
    let sets: [ArgumentSet] = Mirror(reflecting: type.init())
      .children
      .compactMap { child in
        guard
          let codingKey = child.label,
          let parsed = child.value as? ArgumentSetProvider
          else { return nil }

        let key = InputKey(name: codingKey, parent: parent)
        return parsed.argumentSet(for: key)
    }

    guard let repeatedPositional = sets.firstIndex(where: { $0.firstRepeatedPositionalArgument != nil })
      else { return nil }
    guard let positionalFollowingRepeated = sets[repeatedPositional...]
      .dropFirst()
      .first(where: { $0.firstPositionalArgument != nil })
    else { return nil }

    let firstRepeatedPositionalArgument: ArgumentDefinition = sets[repeatedPositional].firstRepeatedPositionalArgument!
    let positionalFollowingRepeatedArgument: ArgumentDefinition = positionalFollowingRepeated.firstPositionalArgument!
    return Error(
      repeatedPositionalArgument: firstRepeatedPositionalArgument.help.keys.first!.name,
      positionalArgumentFollowingRepeated: positionalFollowingRepeatedArgument.help.keys.first!.name)
  }
}

/// Ensure that all arguments have corresponding coding keys
struct ParsableArgumentsCodingKeyValidator: ParsableArgumentsValidator {

  private struct Validator: Decoder {
    let argumentKeys: [InputKey]

    enum ValidationResult: Swift.Error {
      case success
      case missingCodingKeys([InputKey])
    }

    let codingPath: [CodingKey] = []
    let userInfo: [CodingUserInfoKey : Any] = [:]

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
      fatalError()
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
      fatalError()
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
      let missingKeys = argumentKeys.filter { Key(stringValue: $0.name) == nil }
      if missingKeys.isEmpty {
        throw ValidationResult.success
      } else {
        throw ValidationResult.missingCodingKeys(missingKeys)
      }
    }
  }

  /// This error indicates that an option, a flag, or an argument of
  /// a `ParsableArguments` is defined without a corresponding `CodingKey`.
  struct MissingKeysError: ParsableArgumentsValidatorError, CustomStringConvertible {
    let missingCodingKeys: [InputKey]

    var description: String {
      let resolution = """
        To resolve this error, make sure that all properties have corresponding
        cases in your custom `CodingKey` enumeration.
        """

      if missingCodingKeys.count > 1 {
        return """
          Arguments \(missingCodingKeys.map({ "`\($0)`" }).joined(separator: ",")) \
          are defined without corresponding `CodingKey`s.

          \(resolution)
          """
      } else {
        return """
          Argument `\(missingCodingKeys[0])` is defined without a corresponding \
          `CodingKey`.

          \(resolution)
          """
      }
    }

    var kind: ValidatorErrorKind {
      .failure
    }
  }

  struct InvalidDecoderError: ParsableArgumentsValidatorError, CustomStringConvertible {
    let type: ParsableArguments.Type

    var description: String {
      """
      The implementation of `init(from:)` for `\(type)`
      is not compatible with ArgumentParser. To resolve this issue, make sure
      that `init(from:)` calls the `container(keyedBy:)` method on the given
      decoder and decodes each of its properties using the returned decoder.
      """
    }

    var kind: ValidatorErrorKind {
      .failure
    }
  }

  static func validate(_ type: ParsableArguments.Type, parent: InputKey?) -> ParsableArgumentsValidatorError? {
    let argumentKeys: [InputKey] = Mirror(reflecting: type.init())
      .children
      .compactMap { child in
        guard
          let codingKey = child.label,
          let _ = child.value as? ArgumentSetProvider
          else { return nil }

        // Property wrappers have underscore-prefixed names
        return InputKey(name: codingKey, parent: parent)
    }
    guard argumentKeys.count > 0 else {
      return nil
    }
    do {
      let _ = try type.init(from: Validator(argumentKeys: argumentKeys))
      return InvalidDecoderError(type: type)
    } catch let result as Validator.ValidationResult {
      switch result {
      case .missingCodingKeys(let keys):
        return MissingKeysError(missingCodingKeys: keys)
      case .success:
        return nil
      }
    } catch {
      fatalError("Unexpected validation error: \(error)")
    }
  }
}

/// Ensure argument names are unique within a `ParsableArguments` or `ParsableCommand`.
struct ParsableArgumentsUniqueNamesValidator: ParsableArgumentsValidator {
  struct Error: ParsableArgumentsValidatorError, CustomStringConvertible {
    var duplicateNames: [String: Int] = [:]

    var description: String {
      duplicateNames.map { entry in
        "Multiple (\(entry.value)) `Option` or `Flag` arguments are named \"\(entry.key)\"."
      }.joined(separator: "\n")
    }

    var kind: ValidatorErrorKind { .failure }
  }

  static func validate(_ type: ParsableArguments.Type, parent: InputKey?) -> ParsableArgumentsValidatorError? {
    let argSets: [ArgumentSet] = Mirror(reflecting: type.init())
      .children
      .compactMap { child in
        guard
          let codingKey = child.label,
          let parsed = child.value as? ArgumentSetProvider
          else { return nil }

        let key = InputKey(name: codingKey, parent: parent)
        return parsed.argumentSet(for: key)
    }

    let countedNames: [String: Int] = argSets.reduce(into: [:]) { countedNames, args in
      for name in args.content.flatMap({ $0.names }) {
        countedNames[name.synopsisString, default: 0] += 1
      }
    }

    let duplicateNames = countedNames.filter { $0.value > 1 }
    return duplicateNames.isEmpty
      ? nil
      : Error(duplicateNames: duplicateNames)
  }
}

struct NonsenseFlagsValidator: ParsableArgumentsValidator {
  struct Error: ParsableArgumentsValidatorError, CustomStringConvertible {
    var names: [String]

    var description: String {
      """
      One or more Boolean flags is declared with an initial value of `true`.
      This results in the flag always being `true`, no matter whether the user
      specifies the flag or not.

      To resolve this error, change the default to `false`, provide a value
      for the `inversion:` parameter, or remove the `@Flag` property wrapper
      altogether.

      Affected flag(s):
      \(names.joined(separator: "\n"))
      """
    }

    var kind: ValidatorErrorKind { .warning }
  }

  static func validate(_ type: ParsableArguments.Type, parent: InputKey?) -> ParsableArgumentsValidatorError? {
    let argSets: [ArgumentSet] = Mirror(reflecting: type.init())
      .children
      .compactMap { child in
        guard
          let codingKey = child.label,
          let parsed = child.value as? ArgumentSetProvider
          else { return nil }

        let key = InputKey(name: codingKey, parent: parent)
        return parsed.argumentSet(for: key)
    }

    let nonsenseFlags: [String] = argSets.flatMap { args -> [String] in
      args.compactMap { def in
        if case .nullary = def.update,
           !def.help.isComposite,
           def.help.options.contains(.isOptional),
           def.help.defaultValue == "true"
        {
          return def.unadornedSynopsis
        } else {
          return nil
        }
      }
    }

    return nonsenseFlags.isEmpty
      ? nil
      : Error(names: nonsenseFlags)
  }
}

/// A type that can be parsed from a program's command-line arguments.
///
/// When you implement a `ParsableArguments` type, all properties must be declared with
/// one of the four property wrappers provided by the `ArgumentParser` library.
public protocol ParsableArguments: Decodable {
  /// Creates an instance of this parsable type using the definitions
  /// given by each property's wrapper.
  init()

  /// Validates the properties of the instance after parsing.
  ///
  /// Implement this method to perform validation or other processing after
  /// creating a new instance from command-line arguments.
  mutating func validate() throws

  /// The label to use for "Error: ..." messages from this type. (experimental)
  static var _errorLabel: String { get }
}

/// A type that provides the `ParsableCommand` interface to a `ParsableArguments` type.
struct _WrappedParsableCommand<P: ParsableArguments>: ParsableCommand {
  static var _commandName: String {
    let name = String(describing: P.self).convertedToSnakeCase()

    // If the type is named something like "TransformOptions", we only want
    // to use "transform" as the command name.
    if let optionsRange = name.range(of: "_options"),
      optionsRange.upperBound == name.endIndex
    {
      return String(name[..<optionsRange.lowerBound])
    } else {
      return name
    }
  }

  @OptionGroup var options: P
}

extension ParsableArguments {
  public mutating func validate() throws {}

  /// This type as-is if it conforms to `ParsableCommand`, or wrapped in the
  /// `ParsableCommand` wrapper if not.
  internal static var asCommand: ParsableCommand.Type {
    self as? ParsableCommand.Type ?? _WrappedParsableCommand<Self>.self
  }

  public static var _errorLabel: String {
    "Error"
  }
}

// MARK: - API

extension ParsableArguments {
  /// Parses a new instance of this type from command-line arguments.
  ///
  /// - Parameter arguments: An array of arguments to use for parsing. If
  ///   `arguments` is `nil`, this uses the program's command-line arguments.
  /// - Returns: A new instance of this type.
  public static func parse(
    _ arguments: [String]? = nil
  ) throws -> Self {
    // Parse the command and unwrap the result if necessary.
    switch try self.asCommand.parseAsRoot(arguments) {
    case let helpCommand as HelpCommand:
      throw ParserError.helpRequested(visibility: helpCommand.visibility)
    case let result as _WrappedParsableCommand<Self>:
      return result.options
    case var result as Self:
      do {
        try result.validate()
      } catch {
        throw ParserError.userValidationError(error)
      }
      return result
    default:
      // TODO: this should be a "wrong command" message
      throw ParserError.invalidState
    }
  }

  /// Returns a brief message for the given error.
  ///
  /// - Parameter error: An error to generate a message for.
  /// - Returns: A message that can be displayed to the user.
  public static func message(
    for error: Error
  ) -> String {
    MessageInfo(error: error, type: self).message
  }

  /// Returns a full message for the given error, including usage information,
  /// if appropriate.
  ///
  /// - Parameter error: An error to generate a message for.
  /// - Returns: A message that can be displayed to the user.
  public static func fullMessage(
    for error: Error
  ) -> String {
    MessageInfo(error: error, type: self).fullText(for: self)
  }

  /// Returns the text of the help screen for this type.
  ///
  /// - Parameters:
  ///   - columns: The column width to use when wrapping long line in the
  ///     help screen. If `columns` is `nil`, uses the current terminal
  ///     width, or a default value of `80` if the terminal width is not
  ///     available.
  /// - Returns: The full help screen for this type.
  @_disfavoredOverload
  @available(*, deprecated, message: "Use helpMessage(includeHidden:columns:) instead.")
  public static func helpMessage(
    columns: Int?
  ) -> String {
    helpMessage(includeHidden: false, columns: columns)
  }

  /// Returns the text of the help screen for this type.
  ///
  /// - Parameters:
  ///   - includeHidden: Include hidden help information in the generated
  ///     message.
  ///   - columns: The column width to use when wrapping long line in the
  ///     help screen. If `columns` is `nil`, uses the current terminal
  ///     width, or a default value of `80` if the terminal width is not
  ///     available.
  /// - Returns: The full help screen for this type.
  public static func helpMessage(
    includeHidden: Bool = false,
    columns: Int? = nil
  ) -> String {
    HelpGenerator(self, visibility: includeHidden ? .hidden : .default)
      .rendered(screenWidth: columns)
  }

  /// Returns the exit code for the given error.
  ///
  /// The returned code is the same exit code that is used if `error` is passed
  /// to `exit(withError:)`.
  ///
  /// - Parameter error: An error to generate an exit code for.
  /// - Returns: The exit code for `error`.
  public static func exitCode(
    for error: Error
  ) -> ExitCode {
    MessageInfo(error: error, type: self).exitCode
  }

  /// Terminates execution with a message and exit code that is appropriate
  /// for the given error.
  ///
  /// If the `error` parameter is `nil`, this method prints nothing and exits
  /// with code `EXIT_SUCCESS`. If `error` represents a help request or
  /// another `CleanExit` error, this method prints help information and
  /// exits with code `EXIT_SUCCESS`. Otherwise, this method prints a relevant
  /// error message and exits with code `EX_USAGE` or `EXIT_FAILURE`.
  ///
  /// - Parameter error: The error to use when exiting, if any.
  public static func exit(
    withError error: Error? = nil
  ) -> Never {
    guard let error = error else {
      Platform.exit(ExitCode.success.rawValue)
    }

    let messageInfo = MessageInfo(error: error, type: self)
    let fullText = messageInfo.fullText(for: self)
    if !fullText.isEmpty {
      if messageInfo.shouldExitCleanly {
        print(fullText)
      } else {
        print(fullText, to: &Platform.standardError)
      }
    }
    Platform.exit(messageInfo.exitCode.rawValue)
  }

  /// Parses a new instance of this type from command-line arguments or exits
  /// with a relevant message.
  ///
  /// - Parameter arguments: An array of arguments to use for parsing. If
  ///   `arguments` is `nil`, this uses the program's command-line arguments.
  public static func parseOrExit(
    _ arguments: [String]? = nil
  ) -> Self {
    do {
      return try parse(arguments)
    } catch {
      exit(withError: error)
    }
  }
}

/// Unboxes the given value if it is a `nil` value.
///
/// If the value passed is the `.none` case of any optional type, this function
/// returns `nil`.
///
///     let intAsAny = (1 as Int?) as Any
///     let nilAsAny = (nil as Int?) as Any
///     nilOrValue(intAsAny)      // Optional(1) as Any?
///     nilOrValue(nilAsAny)      // nil as Any?
func nilOrValue(_ value: Any) -> Any? {
  if case Optional<Any>.none = value {
    return nil
  } else {
    return value
  }
}

/// Existential protocol for property wrappers, so that they can provide
/// the argument set that they define.
protocol ArgumentSetProvider {
  func argumentSet(for key: InputKey) -> ArgumentSet

  var _visibility: ArgumentVisibility { get }
}

extension ArgumentSetProvider {
  var _visibility: ArgumentVisibility { .default }
}

extension ArgumentSet {
  init(_ type: ParsableArguments.Type, visibility: ArgumentVisibility, parent: InputKey?) {
    #if DEBUG
    do {
      try type._validate(parent: parent)
    } catch {
      assertionFailure("\(error)")
    }
    #endif

    let a: [ArgumentSet] = Mirror(reflecting: type.init())
      .children
      .compactMap { child -> ArgumentSet? in
        guard let codingKey = child.label else { return nil }

        if let parsed = child.value as? ArgumentSetProvider {
          guard parsed._visibility.isAtLeastAsVisible(as: visibility)
            else { return nil }

          let key = InputKey(name: codingKey, parent: parent)
          return parsed.argumentSet(for: key)
        } else {
          let arg = ArgumentDefinition(
            unparsedKey: codingKey,
            default: nilOrValue(child.value), parent: parent)

          // Save a non-wrapped property as is
          return ArgumentSet(arg)
        }
      }
    self.init(
      a.joined().filter { $0.help.visibility.isAtLeastAsVisible(as: visibility) })
  }
}

/// The fatal error message to display when someone accesses a
/// `ParsableArguments` type after initializing it directly.
internal let directlyInitializedError = """

  --------------------------------------------------------------------
  Can't read a value from a parsable argument definition.

  This error indicates that a property declared with an `@Argument`,
  `@Option`, `@Flag`, or `@OptionGroup` property wrapper was neither
  initialized to a value nor decoded from command-line arguments.

  To get a valid value, either call one of the static parsing methods
  (`parse`, `parseAsRoot`, or `main`) or define an initializer that
  initializes _every_ property of your parsable type.
  --------------------------------------------------------------------

  """

/// A type that can be expressed as a command-line argument.
public protocol ExpressibleByArgument {
  /// Creates a new instance of this type from a command-line-specified
  /// argument.
  init?(argument: String)

  /// The description of this instance to show as a default value in a
  /// command-line tool's help screen.
  var defaultValueDescription: String { get }

  /// An array of all possible strings that can convert to a value of this
  /// type.
  ///
  /// The default implementation of this property returns an empty array.
  static var allValueStrings: [String] { get }

  /// The completion kind to use for options or arguments of this type that
  /// don't explicitly declare a completion kind.
  ///
  /// The default implementation of this property returns `.default`.
  static var defaultCompletionKind: CompletionKind { get }
}

extension ExpressibleByArgument {
  public var defaultValueDescription: String {
    "\(self)"
  }

  public static var allValueStrings: [String] { [] }

  public static var defaultCompletionKind: CompletionKind {
    .default
  }
}

extension ExpressibleByArgument where Self: CaseIterable {
  public static var allValueStrings: [String] {
    self.allCases.map { String(describing: $0) }
  }

  public static var defaultCompletionKind: CompletionKind {
    .list(allValueStrings)
  }
}

extension ExpressibleByArgument where Self: CaseIterable, Self: RawRepresentable, RawValue: ExpressibleByArgument {
  public static var allValueStrings: [String] {
    self.allCases.map(\.rawValue.defaultValueDescription)
  }
}

extension ExpressibleByArgument where Self: RawRepresentable, RawValue: ExpressibleByArgument {
  public var defaultValueDescription: String {
    rawValue.defaultValueDescription
  }
}

extension String: ExpressibleByArgument {
  public init?(argument: String) {
    self = argument
  }
}

extension RawRepresentable where Self: ExpressibleByArgument, RawValue: ExpressibleByArgument {
  public init?(argument: String) {
    if let value = RawValue(argument: argument) {
      self.init(rawValue: value)
    } else {
      return nil
    }
  }
}

// MARK: LosslessStringConvertible

extension LosslessStringConvertible where Self: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(argument)
  }
}

extension Int: ExpressibleByArgument {}
extension Int8: ExpressibleByArgument {}
extension Int16: ExpressibleByArgument {}
extension Int32: ExpressibleByArgument {}
extension Int64: ExpressibleByArgument {}
extension UInt: ExpressibleByArgument {}
extension UInt8: ExpressibleByArgument {}
extension UInt16: ExpressibleByArgument {}
extension UInt32: ExpressibleByArgument {}
extension UInt64: ExpressibleByArgument {}

extension Float: ExpressibleByArgument {}
extension Double: ExpressibleByArgument {}

extension Bool: ExpressibleByArgument {}

/// A type that represents the different possible flags to be used by a
/// `@Flag` property.
///
/// For example, the `Size` enumeration declared here can be used as the type of
/// a `@Flag` property:
///
///     enum Size: String, EnumerableFlag {
///         case small, medium, large, extraLarge
///     }
///
///     struct Example: ParsableCommand {
///         @Flag var sizes: [Size]
///
///         mutating func run() {
///             print(sizes)
///         }
///     }
///
/// By default, each case name is converted to a flag by using the `.long` name
/// specification, so a user can call `example` like this:
///
///     $ example --small --large
///     [.small, .large]
///
/// Provide alternative or additional name specifications for each case by
/// implementing the `name(for:)` static method on your `EnumerableFlag` type.
///
///     extension Size {
///         static func name(for value: Self) -> NameSpecification {
///             switch value {
///             case .extraLarge:
///                 return [.customShort("x"), .long]
///             default:
///                 return .shortAndLong
///             }
///         }
///     }
///
/// With this extension, a user can use short or long versions of the flags:
///
///     $ example -s -l -x --medium
///     [.small, .large, .extraLarge, .medium]
public protocol EnumerableFlag: CaseIterable, Equatable {
  /// Returns the name specification to use for the given flag.
  ///
  /// The default implementation for this method always returns `.long`.
  /// Implement this method for your custom `EnumerableFlag` type to provide
  /// different name specifications for different cases.
  static func name(for value: Self) -> NameSpecification

  /// Returns the help information to show for the given flag.
  ///
  /// The default implementation for this method always returns `nil`, which
  /// groups the flags together with the help provided in the `@Flag`
  /// declaration. Implement this method for your custom type to provide
  /// different help information for each flag.
  static func help(for value: Self) -> ArgumentHelp?
}

extension EnumerableFlag {
  public static func name(for value: Self) -> NameSpecification {
    .long
  }

  public static func help(for value: Self) -> ArgumentHelp? {
    nil
  }
}

/// The configuration for a command.
public struct CommandConfiguration {
  /// The name of the command to use on the command line.
  ///
  /// If `nil`, the command name is derived by converting the name of
  /// the command type to hyphen-separated lowercase words.
  public var commandName: String?

  /// The name of this command's "super-command". (experimental)
  ///
  /// Use this when a command is part of a group of commands that are installed
  /// with a common dash-prefix, like `git`'s and `swift`'s constellation of
  /// independent commands.
  public var _superCommandName: String?

  /// A one-line description of this command.
  public var abstract: String

  /// A customized usage string to be shown in the help display and error
  /// messages.
  ///
  /// If `usage` is `nil`, the help display and errors show the autogenerated
  /// usage string. To hide the usage string entirely, set `usage` to the empty
  /// string.
  public var usage: String?

  /// A longer description of this command, to be shown in the extended help
  /// display.
  public var discussion: String

  /// Version information for this command.
  public var version: String

  /// A Boolean value indicating whether this command should be shown in
  /// the extended help display.
  public var shouldDisplay: Bool

  /// An array of the types that define subcommands for this command.
  public var subcommands: [ParsableCommand.Type]

  /// The default command type to run if no subcommand is given.
  public var defaultSubcommand: ParsableCommand.Type?

  /// Flag names to be used for help.
  public var helpNames: NameSpecification?

  /// Creates the configuration for a command.
  ///
  /// - Parameters:
  ///   - commandName: The name of the command to use on the command line. If
  ///     `commandName` is `nil`, the command name is derived by converting
  ///     the name of the command type to hyphen-separated lowercase words.
  ///   - abstract: A one-line description of the command.
  ///   - usage: A custom usage description for the command. When you provide
  ///     a non-`nil` string, the argument parser uses `usage` instead of
  ///     automatically generating a usage description. Passing an empty string
  ///     hides the usage string altogether.
  ///   - discussion: A longer description of the command.
  ///   - version: The version number for this command. When you provide a
  ///     non-empty string, the argument parser prints it if the user provides
  ///     a `--version` flag.
  ///   - shouldDisplay: A Boolean value indicating whether the command
  ///     should be shown in the extended help display.
  ///   - subcommands: An array of the types that define subcommands for the
  ///     command.
  ///   - defaultSubcommand: The default command type to run if no subcommand
  ///     is given.
  ///   - helpNames: The flag names to use for requesting help, when combined
  ///     with a simulated Boolean property named `help`. If `helpNames` is
  ///     `nil`, the names are inherited from the parent command, if any, or
  ///     are `-h` and `--help`.
  public init(
    commandName: String? = nil,
    abstract: String = "",
    usage: String? = nil,
    discussion: String = "",
    version: String = "",
    shouldDisplay: Bool = true,
    subcommands: [ParsableCommand.Type] = [],
    defaultSubcommand: ParsableCommand.Type? = nil,
    helpNames: NameSpecification? = nil
  ) {
    self.commandName = commandName
    self.abstract = abstract
    self.usage = usage
    self.discussion = discussion
    self.version = version
    self.shouldDisplay = shouldDisplay
    self.subcommands = subcommands
    self.defaultSubcommand = defaultSubcommand
    self.helpNames = helpNames
  }

  /// Creates the configuration for a command with a "super-command".
  /// (experimental)
  public init(
    commandName: String? = nil,
    _superCommandName: String,
    abstract: String = "",
    usage: String? = nil,
    discussion: String = "",
    version: String = "",
    shouldDisplay: Bool = true,
    subcommands: [ParsableCommand.Type] = [],
    defaultSubcommand: ParsableCommand.Type? = nil,
    helpNames: NameSpecification? = nil
  ) {
    self.commandName = commandName
    self._superCommandName = _superCommandName
    self.abstract = abstract
    self.usage = usage
    self.discussion = discussion
    self.version = version
    self.shouldDisplay = shouldDisplay
    self.subcommands = subcommands
    self.defaultSubcommand = defaultSubcommand
    self.helpNames = helpNames
  }
}

extension CommandConfiguration {
  @available(*, deprecated, message: "Use the memberwise initializer with the usage parameter.")
  public init(
    commandName: String?,
    abstract: String,
    discussion: String,
    version: String,
    shouldDisplay: Bool,
    subcommands: [ParsableCommand.Type],
    defaultSubcommand: ParsableCommand.Type?,
    helpNames: NameSpecification?
  ) {
    self.init(
      commandName: commandName,
      abstract: abstract,
      usage: "",
      discussion: discussion,
      version: version,
      shouldDisplay: shouldDisplay,
      subcommands: subcommands,
      defaultSubcommand: defaultSubcommand,
      helpNames: helpNames)
  }
}

/// A type that can be executed asynchronously, as part of a nested tree of
/// commands.
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
public protocol AsyncParsableCommand: ParsableCommand {
  /// The behavior or functionality of this command.
  ///
  /// Implement this method in your `ParsableCommand`-conforming type with the
  /// functionality that this command represents.
  ///
  /// This method has a default implementation that prints the help screen for
  /// this command.
  mutating func run() async throws
}

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncParsableCommand {
  /// Executes this command, or one of its subcommands, with the program's
  /// command-line arguments.
  ///
  /// Instead of calling this method directly, you can add `@main` to the root
  /// command for your command-line tool.
  public static func main() async {
    do {
      var command = try parseAsRoot()
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      exit(withError: error)
    }
  }
}

/// A type that can designate an `AsyncParsableCommand` as the program's
/// entry point.
///
/// See the ``AsyncParsableCommand`` documentation for usage information.
@available(
  swift, deprecated: 5.6,
  message: "Use @main directly on your root `AsyncParsableCommand` type.")
public protocol AsyncMainProtocol {
  associatedtype Command: ParsableCommand
}

@available(swift, deprecated: 5.6)
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
extension AsyncMainProtocol {
  /// Executes the designated command type, or one of its subcommands, with
  /// the program's command-line arguments.
  public static func main() async {
    do {
      var command = try Command.parseAsRoot()
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch {
      Command.exit(withError: error)
    }
  }
}


// MARK: Utilities

enum Platform {}

// MARK: Shell

extension Platform {
  /// The name of the user's preferred shell, if detectable from the
  /// environment.
  static var shellName: String? {
#if os(Windows)
    return nil
#else
    // FIXME: This retrieves the user's preferred shell, not necessarily the one currently in use.
    guard let shellVar = getenv("SHELL") else { return nil }
    let shellParts = String(cString: shellVar).split(separator: "/")
    return shellParts.last.map(String.init)
#endif
  }
}

// MARK: Exit codes


extension Platform {
  /// The code for successful exit.
  static var exitCodeSuccess: Int32 {
    EXIT_SUCCESS
  }

  /// The code for exit with a general failure.
  static var exitCodeFailure: Int32 {
    EXIT_FAILURE
  }

  /// The code for exit with a validation failure.
  static var exitCodeValidationFailure: Int32 {
#if os(Windows)
    return ERROR_BAD_ARGUMENTS
#elseif os(WASI)
    return EXIT_FAILURE
#else
    return EX_USAGE
#endif
  }
}

// MARK: Exit function

extension Platform {
  /// Complete execution with the given exit code.
  static func exit(_ code: Int32) -> Never {
#if canImport(Glibc)
    Glibc.exit(code)
#elseif canImport(Musl)
    Musl.exit(code)
#elseif canImport(Darwin)
    Darwin.exit(code)
#elseif canImport(CRT)
    ucrt._exit(code)
#elseif canImport(WASILibc)
    WASILibc.exit(code)
#endif
  }
}

// MARK: Standard error

extension Platform {
  /// A type that represents the `stderr` output stream.
  struct StandardError: TextOutputStream {
    mutating func write(_ string: String) {
      for byte in string.utf8 { putc(numericCast(byte), stderr) }
    }
  }

  /// The `stderr` output stream.
  static var standardError = StandardError()
}

// MARK: Terminal size

#if canImport(Glibc)
func ioctl(_ a: Int32, _ b: Int32, _ p: UnsafeMutableRawPointer) -> Int32 {
  ioctl(CInt(a), UInt(b), p)
}
#endif

extension Platform {
  /// The default terminal size.
  static var defaultTerminalSize: (width: Int, height: Int) {
    (80, 25)
  }

  /// Returns the current terminal size, or the default if the size is
  /// unavailable.
  static func terminalSize() -> (width: Int, height: Int) {
#if os(WASI)
    // WASI doesn't yet support terminal size
    return defaultTerminalSize
#elseif os(Windows)
    var csbi: CONSOLE_SCREEN_BUFFER_INFO = CONSOLE_SCREEN_BUFFER_INFO()
    guard GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi) else {
      return defaultTerminalSize
    }
    return (width: Int(csbi.srWindow.Right - csbi.srWindow.Left) + 1,
            height: Int(csbi.srWindow.Bottom - csbi.srWindow.Top) + 1)
#else
    var w = winsize()
#if os(OpenBSD)
    // TIOCGWINSZ is a complex macro, so we need the flattened value.
    let tiocgwinsz = Int32(0x40087468)
    let err = ioctl(STDOUT_FILENO, tiocgwinsz, &w)
#elseif canImport(Musl)
    let err = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w)
#else
    let err = ioctl(STDOUT_FILENO, TIOCGWINSZ, &w)
#endif
    let width = Int(w.ws_col)
    let height = Int(w.ws_row)
    guard err == 0 else { return defaultTerminalSize }
    return (width: width > 0 ? width : defaultTerminalSize.width,
            height: height > 0 ? height : defaultTerminalSize.height)
#endif
  }

  /// The current terminal size, or the default if the width is unavailable.
  static var terminalWidth: Int {
    terminalSize().width
  }
}


extension Collection {
  func mapEmpty(_ replacement: () -> Self) -> Self {
    isEmpty ? replacement() : self
  }
}

extension MutableCollection {
  mutating func withEach(_ body: (inout Element) throws -> Void) rethrows {
    var i = startIndex
    while i < endIndex {
      try body(&self[i])
      formIndex(after: &i)
    }
  }
}

extension Sequence where Element: Hashable {
  /// Returns an array with only the unique elements of this sequence, in the
  /// order of the first occurrence of each unique element.
  func uniquing() -> [Element] {
    var seen = Set<Element>()
    return self.filter { seen.insert($0).0 }
  }

  /// Returns an array, collapsing runs of consecutive equal elements into
  /// the first element of each run.
  ///
  ///     [1, 2, 2, 2, 3, 3, 2, 2, 1, 1, 1].uniquingAdjacentElements()
  ///     // [1, 2, 3, 2, 1]
  func uniquingAdjacentElements() -> [Element] {
    var iterator = makeIterator()
    guard let first = iterator.next()
      else { return [] }

    var result = [first]
    while let element = iterator.next() {
      if result.last != element {
        result.append(element)
      }
    }
    return result
  }
}


extension StringProtocol where SubSequence == Substring {
  func wrapped(to columns: Int, wrappingIndent: Int = 0) -> String {
    let columns = columns - wrappingIndent
    guard columns > 0 else {
      // Skip wrapping logic if the number of columns is less than 1 in release
      // builds and assert in debug builds.
      assertionFailure("`columns - wrappingIndent` should be always be greater than 0.")
      return ""
    }

    var result: [Substring] = []

    var currentIndex = startIndex

    while true {
      let nextChunk = self[currentIndex...].prefix(columns)
      if let lastLineBreak = nextChunk.lastIndex(of: "\n") {
        result.append(contentsOf: self[currentIndex..<lastLineBreak].split(separator: "\n", omittingEmptySubsequences: false))
        currentIndex = index(after: lastLineBreak)
      } else if nextChunk.endIndex == self.endIndex {
        result.append(self[currentIndex...])
        break
      } else if let lastSpace = nextChunk.lastIndex(of: " ") {
        result.append(self[currentIndex..<lastSpace])
        currentIndex = index(after: lastSpace)
      } else if let nextSpace = self[currentIndex...].firstIndex(of: " ") {
        result.append(self[currentIndex..<nextSpace])
        currentIndex = index(after: nextSpace)
      } else {
        result.append(self[currentIndex...])
        break
      }
    }

    return result
      .map { $0.isEmpty ? $0 : String(repeating: " ", count: wrappingIndent) + $0 }
      .joined(separator: "\n")
  }

  /// Returns this string prefixed using a camel-case style.
  ///
  /// Example:
  ///
  ///     "hello".addingIntercappedPrefix("my")
  ///     // myHello
  func addingIntercappedPrefix(_ prefix: String) -> String {
    guard let firstChar = first else { return prefix }
    return "\(prefix)\(firstChar.uppercased())\(self.dropFirst())"
  }

  /// Returns this string prefixed using kebab-, snake-, or camel-case style
  /// depending on what can be detected from the string.
  ///
  /// Examples:
  ///
  ///     "hello".addingPrefixWithAutodetectedStyle("my")
  ///     // my-hello
  ///     "hello_there".addingPrefixWithAutodetectedStyle("my")
  ///     // my_hello_there
  ///     "hello-there".addingPrefixWithAutodetectedStyle("my")
  ///     // my-hello-there
  ///     "helloThere".addingPrefixWithAutodetectedStyle("my")
  ///     // myHelloThere
  func addingPrefixWithAutodetectedStyle(_ prefix: String) -> String {
    if contains("-") {
      return "\(prefix)-\(self)"
    } else if contains("_") {
      return "\(prefix)_\(self)"
    } else if first?.isLowercase == true && contains(where: { $0.isUppercase }) {
      return addingIntercappedPrefix(prefix)
    } else {
      return "\(prefix)-\(self)"
    }
  }

  /// Returns a new string with the camel-case-based words of this string
  /// split by the specified separator.
  ///
  /// Examples:
  ///
  ///     "myProperty".convertedToSnakeCase()
  ///     // my_property
  ///     "myURLProperty".convertedToSnakeCase()
  ///     // my_url_property
  ///     "myURLProperty".convertedToSnakeCase(separator: "-")
  ///     // my-url-property
  func convertedToSnakeCase(separator: Character = "_") -> String {
    guard !isEmpty else { return "" }
    var result = ""
    // Whether we should append a separator when we see a uppercase character.
    var separateOnUppercase = true
    for index in indices {
      let nextIndex = self.index(after: index)
      let character = self[index]
      if character.isUppercase {
        if separateOnUppercase && !result.isEmpty {
          // Append the separator.
          result += "\(separator)"
        }
        // If the next character is uppercase and the next-next character is lowercase, like "L" in "URLSession", we should separate words.
        separateOnUppercase = nextIndex < endIndex && self[nextIndex].isUppercase && self.index(after: nextIndex) < endIndex && self[self.index(after: nextIndex)].isLowercase
      } else {
        // If the character is `separator`, we do not want to append another separator when we see the next uppercase character.
        separateOnUppercase = character != separator
      }
      // Append the lowercased character.
      result += character.lowercased()
    }
    return result
  }

  /// Returns the edit distance between this string and the provided target string.
  ///
  /// Uses the Levenshtein distance algorithm internally.
  ///
  /// See: https://en.wikipedia.org/wiki/Levenshtein_distance
  ///
  /// Examples:
  ///
  ///     "kitten".editDistance(to: "sitting")
  ///     // 3
  ///     "bar".editDistance(to: "baz")
  ///     // 1
  func editDistance(to target: String) -> Int {
    let rows = self.count
    let columns = target.count

    if rows <= 0 || columns <= 0 {
      return Swift.max(rows, columns)
    }

    // Trim common prefix and suffix
    var selfStartTrim = self.startIndex
    var targetStartTrim = target.startIndex
    while selfStartTrim < self.endIndex &&
          targetStartTrim < target.endIndex &&
            self[selfStartTrim] == target[targetStartTrim] {
      self.formIndex(after: &selfStartTrim)
      target.formIndex(after: &targetStartTrim)
    }

    var selfEndTrim = self.endIndex
    var targetEndTrim = target.endIndex

    while selfEndTrim > selfStartTrim &&
          targetEndTrim > targetStartTrim {
      let selfIdx = self.index(before: selfEndTrim)
      let targetIdx = target.index(before: targetEndTrim)

      guard self[selfIdx] == target[targetIdx] else {
        break
      }

      selfEndTrim = selfIdx
      targetEndTrim = targetIdx
    }

    // Equal strings
    guard !(selfStartTrim == self.endIndex &&
          targetStartTrim == target.endIndex) else {
      return 0
    }

    // After trimming common prefix and suffix, self is empty.
    guard selfStartTrim < selfEndTrim else {
      return target.distance(from: targetStartTrim,
                             to: targetEndTrim)
    }

    // After trimming common prefix and suffix, target is empty.
    guard targetStartTrim < targetEndTrim else {
      return distance(from: selfStartTrim,
                      to: selfEndTrim)
    }

    let newSelf = self[selfStartTrim..<selfEndTrim]
    let newTarget = target[targetStartTrim..<targetEndTrim]

    let m = newSelf.count
    let n = newTarget.count

    // Initialize the levenshtein matrix with only two rows
    // current and previous.
    var previousRow = [Int](repeating: 0, count: n + 1)
    var currentRow = [Int](0...n)

    var sourceIdx = newSelf.startIndex
    for i in 1...m {
      swap(&previousRow, &currentRow)
      currentRow[0] = i

      var targetIdx = newTarget.startIndex
      for j in 1...n {
        // If characteres are equal for the levenshtein algorithm the
        // minimum will always be the substitution cost, so we can fast
        // path here in order to avoid min calls.
        if newSelf[sourceIdx] == newTarget[targetIdx] {
          currentRow[j] = previousRow[j - 1]
        } else {
          let deletion = previousRow[j]
          let insertion = currentRow[j - 1]
          let substitution = previousRow[j - 1]
          currentRow[j] = Swift.min(deletion, Swift.min(insertion, substitution)) + 1
        }
        // j += 1
        newTarget.formIndex(after: &targetIdx)
      }
      // i += 1
      newSelf.formIndex(after: &sourceIdx)
    }
    return currentRow[n]
  }

  func indentingEachLine(by n: Int) -> String {
    let lines = self.split(separator: "\n", omittingEmptySubsequences: false)
    let spacer = String(repeating: " ", count: n)
    return lines.map {
      $0.isEmpty ? $0 : spacer + $0
    }.joined(separator: "\n")
  }

  func hangingIndentingEachLine(by n: Int) -> String {
    let lines = self.split(
      separator: "\n",
      maxSplits: 1,
      omittingEmptySubsequences: false)
    guard lines.count == 2 else { return lines.joined(separator: "") }
    return "\(lines[0])\n\(lines[1].indentingEachLine(by: n))"
  }

  var nonEmpty: Self? {
    isEmpty ? nil : self
  }
}

final class Tree<Element> {
  var element: Element
  weak var parent: Tree?
  var children: [Tree]

  var isRoot: Bool { parent == nil }
  var isLeaf: Bool { children.isEmpty }
  var hasChildren: Bool { !isLeaf }

  init(_ element: Element) {
    self.element = element
    self.parent = nil
    self.children = []
  }

  func addChild(_ tree: Tree) {
    children.append(tree)
    tree.parent = self
  }
}

extension Tree: Hashable {
  static func == (lhs: Tree<Element>, rhs: Tree<Element>) -> Bool {
    lhs === rhs
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension Tree {
  /// Returns a path of tree nodes that traverses from this node to the first
  /// node (breadth-first) that matches the given predicate.
  func path(toFirstWhere predicate: (Element) -> Bool) -> [Tree] {
    var visited: Set<Tree> = []
    var toVisit: [Tree] = [self]
    var currentIndex = 0

    // For each node, the neighbor that is most efficiently used to reach
    // that node.
    var cameFrom: [Tree: Tree] = [:]

    while let current = toVisit[currentIndex...].first {
      currentIndex += 1
      if predicate(current.element) {
        // Reconstruct the path from `self` to `current`.
        return sequence(first: current, next: { cameFrom[$0] }).reversed()
      }
      visited.insert(current)

      for child in current.children where !visited.contains(child) {
        if !toVisit.contains(child) {
          toVisit.append(child)
        }

        // Coming from `current` is the best path to `neighbor`.
        cameFrom[child] = current
      }
    }

    // Didn't find a path!
    return []
  }
}

extension Tree where Element == ParsableCommand.Type {
  func path(to element: Element) -> [Element] {
    path(toFirstWhere: { $0 == element }).map { $0.element }
  }

  func firstChild(equalTo element: Element) -> Tree? {
    children.first(where: { $0.element == element })
  }

  func firstChild(withName name: String) -> Tree? {
    children.first(where: { $0.element._commandName == name })
  }

  convenience init(root command: ParsableCommand.Type) throws {
    self.init(command)
    for subcommand in command.configuration.subcommands {
      if subcommand == command {
        throw InitializationError.recursiveSubcommand(subcommand)
      }
      try addChild(Tree(root: subcommand))
    }
  }

  enum InitializationError: Error {
    case recursiveSubcommand(ParsableCommand.Type)
  }
}
