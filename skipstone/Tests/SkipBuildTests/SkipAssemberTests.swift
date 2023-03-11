import XCTest
@testable import SkipBuild
import TSCBasic

final class SkipAssemberTests: XCTestCase {
    public func testFileSystem() async throws {
        try fileSystemTest(fs: InMemoryFileSystem())
        try fileSystemTest(fs: localFileSystem)
    }

    public func fileSystemTest<FS: FileSystem>(fs: FS) throws {
        let tmpRoot = try AbsolutePath(validating: UUID().uuidString, relativeTo: AbsolutePath(validating: NSTemporaryDirectory()))

        let baseDir = try AbsolutePath(validating: "one/two/three", relativeTo: tmpRoot)
        try fs.createDirectory(baseDir, recursive: true)
        let dummyFile = baseDir.appending(component: "basic.txt")
        try fs.writeFileContents(dummyFile) { stream in
            stream.write("Hello World")
        }
        let contents = try fs.readFileContents(dummyFile)
        XCTAssertEqual("Hello World", contents)

        XCTAssertEqual(try fs.treeASCIIRepresentation(at: tmpRoot), """
        .
        └─ one
           └─ two
              └─ three
                 └─ basic.txt

        """)

        let reroot = RerootedFileSystemView(fs, rootedAt: baseDir)
        try reroot.writeFileContents(AbsolutePath(validating: "/advanced.txt")) { stream in
            stream.write("Hello Advanced")
        }

        XCTAssertEqual(try fs.treeASCIIRepresentation(at: tmpRoot), """
        .
        └─ one
           └─ two
              └─ three
                 ├─ advanced.txt
                 └─ basic.txt

        """)


        try fs.removeFileTree(tmpRoot)
    }

    func testKotlinScripting() async throws {
        let three = try await SkipSystem.kotlinc(script: "1+2")
        XCTAssertEqual("3", three)

        let x2 = try await SkipSystem.kotlinc(script: "\"x\"+2")
        XCTAssertEqual("x2", x2)
    }


    func testKotlinJSConversion() async throws {
        @Sendable @discardableResult func check(_ kotlin: String, _ expected: String, file: StaticString = #file, line: UInt = #line) async throws -> String {
            let js = try await SkipSystem.kotlinToJS(kotlin)
            XCTAssertTrue(js.contains(expected), "Unexpected output: \(js)", file: file, line: line)
            return js
        }

        try await check("data class Person(val firstName: String? = null, var age: Int?)", """
          function Person(firstName, age) {
            if (firstName === void 0)
              firstName = null;
            this.firstName = firstName;
            this.age = age;
          }
        """)

//        // the remaining checks work, but they are slow since they involve forking the compiler for each individual check
//        return;


        try await check(#"fun someFunction(arg: Int = 1) { "returnString" }"#, """
          function someFunction(arg) {
            if (arg === void 0)
              arg = 1;
            'returnString';
          }
        """)

        try await check("""
        fun someFunction() {
            val numbers = arrayOf(1, 2, 3, 4, 5)
            val doubledNumbers = numbers.map { it * 2 }
            println(doubledNumbers)
        }
        """,
        """
          function someFunction() {
            var numbers = [1, 2, 3, 4, 5];
            var destination = ArrayList_init(numbers.length);
            var tmp$;
            for (tmp$ = 0; tmp$ !== numbers.length; ++tmp$) {
              var item = numbers[tmp$];
              destination.add_11rb$(item * 2 | 0);
            }
            var doubledNumbers = destination;
            println(doubledNumbers);
          }
        """)

        try await check("""
        fun String.upperFirstAndLast(): String {
            val upperFirst = this[0].toUpperCase() + this.substring(1)
            return upperFirst.substring(0, upperFirst.length - 1) + upperFirst.last().toUpperCase()
        }

        fun someFunction() {
            println("kotlin".upperFirstAndLast())
        }
        """,
        """
          function upperFirstAndLast($receiver) {
            var tmp$ = uppercaseChar($receiver.charCodeAt(0));
            var other = $receiver.substring(1);
            var upperFirst = String.fromCharCode(tmp$) + other;
            var endIndex = upperFirst.length - 1 | 0;
            return upperFirst.substring(0, endIndex) + String.fromCharCode(toBoxedChar(uppercaseChar(last(upperFirst))));
          }
          function someFunction() {
            println(upperFirstAndLast('kotlin'));
          }
        """)

        try await check("""
        fun someFunction() {
            for (i in 1..10) println(i)
        }
        """,
        """
          function someFunction() {
            for (var i = 1; i <= 10; i++)
              println(i);
          }
        """)

        try await check("""
        object Singleton {
            val name = "John Doe"
        }
        fun someFunction() {
            println(Singleton.name)
        }
        """,
        """
          function Singleton() {
            Singleton_instance = this;
            this.name = 'John Doe';
          }
          Singleton.$metadata$ = {
            kind: Kind_OBJECT,
            simpleName: 'Singleton',
            interfaces: []
          };
          var Singleton_instance = null;
          function Singleton_getInstance() {
            if (Singleton_instance === null) {
              new Singleton();
            }
            return Singleton_instance;
          }
          function someFunction() {
            println(Singleton_getInstance().name);
          }
        """)

        try await check("""
        fun someFunction() {
            class Person(val name: String, val age: Int)
            val person = Person("John Doe", 30)
            println(person.name)
        }
        """,
        """
          function someFunction$Person(name, age) {
            this.name = name;
            this.age = age;
          }
          someFunction$Person.$metadata$ = {
            kind: Kind_CLASS,
            simpleName: 'Person',
            interfaces: []
          };
          function someFunction() {
            var person = new someFunction$Person('John Doe', 30);
            println(person.name);
          }
        """)

        try await check("""
        fun someFunction() {
            fun divide(a: Int, b: Int): Int {
                try {
                    return a / b
                } catch (e: ArithmeticException) {
                    println("Cannot divide by zero")
                    return 0
                }
            }
            println(divide(10, 2))
        }
        """,
        """
          var ArithmeticException = Kotlin.kotlin.ArithmeticException;
          function someFunction$divide(a, b) {
            try {
              return a / b | 0;
            } catch (e) {
              if (Kotlin.isType(e, ArithmeticException)) {
                println('Cannot divide by zero');
                return 0;
              } else
                throw e;
            }
          }
          function someFunction() {
            var divide = someFunction$divide;
            println(divide(10, 2));
          }
        """)

        try await check("""
        fun someFunction() {
            val x = 10
            val result = when (x) {
                0 -> "Zero"
                in 1..9 -> "Positive single digit number"
                else -> "Positive number"
            }
            println(result)
        }
        """,
        """
          function someFunction() {
            var tmp$;
            var x = 10;
            if (x === 0)
              tmp$ = 'Zero';
            else if (x >= 1 && x <= 9)
              tmp$ = 'Positive single digit number';
            else
              tmp$ = 'Positive number';
            var result = tmp$;
            println(result);
          }
        """)

//        try await check("""
//        fun someFunction() {
//        }
//        """,
//        """
//        """)

    }
}
