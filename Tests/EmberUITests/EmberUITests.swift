import XCTest

final class EmberUITests: XCTestCase {
    private var app: XCUIApplication!
    private var namespace: String!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        namespace = UUID().uuidString
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    private func launch(
        scenario: String = "standard",
        skipOnboarding: Bool = true,
        preserveState: Bool = false,
        query: String? = nil,
        autoOpenFirst: Bool = false,
        openSettings: Bool = false
    ) {
        app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiScenario", scenario,
            "-uiStateNamespace", namespace,
        ]
        if skipOnboarding {
            app.launchArguments.append("-uiSkipOnboarding")
        }
        if preserveState {
            app.launchArguments.append("-uiPreserveState")
        }
        if let query {
            app.launchArguments += ["-uiQuery", query]
        }
        if autoOpenFirst {
            app.launchArguments.append("-uiAutoOpenFirst")
        }
        if openSettings {
            app.launchArguments.append("-uiOpenSettings")
        }
        app.launch()
    }

    func testOnboardingCompletionPersistsAcrossRelaunch() {
        launch(skipOnboarding: false)
        let progress = app.descendants(matching: .any)["onboarding.progress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        #if targetEnvironment(macCatalyst)
        XCTAssertEqual(progress.label, "Step 1 of 6")
        app.terminate()
        launch(preserveState: true)
        XCTAssertTrue(app.descendants(matching: .any)["story.row.1"].waitForExistence(timeout: 5))
        #else
        for step in 1...6 {
            XCTAssertEqual(progress.label, "Step \(step) of 6")
            let next = app.buttons["onboarding.next"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
            if step < 6 {
                let advanced = NSPredicate(format: "label == %@", "Step \(step + 1) of 6")
                expectation(for: advanced, evaluatedWith: progress)
                waitForExpectations(timeout: 5)
            }
        }
        XCTAssertTrue(app.descendants(matching: .any)["story.row.1"].waitForExistence(timeout: 5))

        app.terminate()
        launch(skipOnboarding: false, preserveState: true)

        XCTAssertFalse(app.otherElements["onboarding.progress"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["story.row.1"].waitForExistence(timeout: 5))
        #endif
    }

    func testStandardFeedDetailBookmarkAndComments() {
        launch(autoOpenFirst: true)

        let bookmark = app.descendants(matching: .any)["story.bookmark"].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()

        let comment = app.descendants(matching: .any)["comment.row.101"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        let reply = app.descendants(matching: .any)["comment.row.1011"]
        XCTAssertTrue(reply.exists)
        clickCommentToggle(id: 101, label: "Collapse thread")
        // After collapse, reply 1011 should leave the visible tree.
        XCTAssertTrue(reply.waitForNonExistence(timeout: 2))

        clickCommentToggle(id: 101, label: "Expand thread")
        XCTAssertTrue(reply.waitForExistence(timeout: 2))
    }

    private func clickCommentToggle(id: Int, label: String) {
        let comment = app.descendants(matching: .any)["comment.row.\(id)"].firstMatch
        let toggle = comment.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", label)
        ).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        #if targetEnvironment(macCatalyst)
        app.activate()
        toggle.click()
        #else
        toggle.tap()
        #endif
    }

    func testEmptyAndFailureScenariosRenderDeterministically() {
        launch(scenario: "emptyFeed")
        XCTAssertTrue(app.descendants(matching: .any)["state.empty"].waitForExistence(timeout: 5))

        app.terminate()
        namespace = UUID().uuidString
        launch(scenario: "feedFailure")
        XCTAssertTrue(app.descendants(matching: .any)["state.error"].waitForExistence(timeout: 5))
    }

    #if !targetEnvironment(macCatalyst)
    func testIOSNavigationSearchAndSettings() {
        launch(query: "Swift")

        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["story.row.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["search.sort"].exists)

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["state.empty"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        let form = app.descendants(matching: .any)["settings.form"].firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        // "Personalize" is below the fold on iPhone, so scroll it into the
        // accessibility hierarchy before asserting it exists.
        let personalize = app.buttons["settings.personalize"]
        var scrolls = 0
        while !personalize.exists && scrolls < 5 {
            form.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(personalize.exists)
    }
    #else
    func testCatalystSidebarSearchSavedAndSettings() {
        launch(query: "Swift")

        let search = app.staticTexts["sidebar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let result = app.descendants(matching: .any)["desktop.story.row.1"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))

        app.activate()
        app.staticTexts["sidebar.saved"].tap()

        app.terminate()
        namespace = UUID().uuidString
        launch(openSettings: true)
        XCTAssertTrue(app.descendants(matching: .any)["settings.form"].waitForExistence(timeout: 5))
    }
    #endif
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
