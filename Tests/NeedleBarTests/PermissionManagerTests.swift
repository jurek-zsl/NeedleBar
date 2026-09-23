import XCTest
@testable import NeedleBarCore

final class PermissionManagerTests: XCTestCase {
    func testOnlyFeaturePermissionsArePresented() {
        XCTAssertEqual(
            PermissionType.allCases,
            [.accessibility, .reminders, .calendar, .notesAutomation]
        )
    }

    func testEveryPermissionExplainsItsCapabilityAndHasASettingsDestination() {
        for permission in PermissionType.allCases {
            XCTAssertFalse(permission.title.isEmpty)
            XCTAssertFalse(permission.reasonDescription.isEmpty)
            XCTAssertNotNil(permission.settingsURL)
        }
    }

    func testToolsDeclareOnlyThePermissionTheyActuallyUse() {
        XCTAssertEqual(StartTimerTool().requiredPermission, .accessibility)
        XCTAssertEqual(CreateReminderTool().requiredPermission, .reminders)
        XCTAssertEqual(CreateCalendarEventTool().requiredPermission, .calendar)
        XCTAssertEqual(SearchNotesTool().requiredPermission, .notesAutomation)
        XCTAssertEqual(GetBatteryStatusTool().requiredPermission, nil)
    }
}
