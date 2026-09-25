import XCTest
@testable import DrawThingsClient

final class DTLoggerTests: XCTestCase {

    private var savedLevel: DTLogLevel = .none
    private var savedEnabled = true

    override func setUp() {
        super.setUp()
        savedLevel = DTLogger.minimumLevel
        savedEnabled = DTLogger.shared.isEnabled
    }

    override func tearDown() {
        DTLogger.minimumLevel = savedLevel
        DTLogger.shared.isEnabled = savedEnabled
        super.tearDown()
    }

    func testLoggingIsOffByDefault() {
        XCTAssertEqual(DTLogger.minimumLevel, .none)
        XCTAssertFalse(DTLogger.isLogging(.fault))
    }

    func testMinimumLevelFiltersLowerLevels() {
        DTLogger.minimumLevel = .warning
        XCTAssertFalse(DTLogger.isLogging(.debug))
        XCTAssertFalse(DTLogger.isLogging(.info))
        XCTAssertTrue(DTLogger.isLogging(.warning))
        XCTAssertTrue(DTLogger.isLogging(.error))
        XCTAssertFalse(DTLogger.isLogging(.none))
    }

    func testIsEnabledOverridesLevel() {
        DTLogger.minimumLevel = .debug
        DTLogger.shared.isEnabled = false
        XCTAssertFalse(DTLogger.isLogging(.fault))
    }

    func testMessageIsNotEvaluatedWhenFiltered() {
        DTLogger.minimumLevel = .error
        var evaluated = false
        DTLogger.debug({ evaluated = true; return "skipped" }())
        XCTAssertFalse(evaluated)
    }

    func testConcurrentUse() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    DTLogger.minimumLevel = i.isMultiple(of: 2) ? .debug : .none
                    DTLogger.debug("concurrent \(i)", category: .grpc)
                }
            }
        }
    }

    @available(*, deprecated)
    func testDeprecatedClientLoggerForwards() {
        DrawThingsClientLogger.minimumLevel = .notice
        XCTAssertEqual(DTLogger.minimumLevel, .warning)
    }
}
