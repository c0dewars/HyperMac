import Foundation

@main enum ScrollingChecks {
    static func main() throws {
        var gesture = ScrollingGesture()
        precondition(gesture.consume(delta: 3, time: 0, phase: .began, momentum: false, precise: true) == nil)
        precondition(gesture.consume(delta: 6, time: 0.02, phase: .changed, momentum: false, precise: true) == .left)
        for tick in 2...50 {
            precondition(gesture.consume(delta: 20, time: Double(tick) / 50, phase: .changed, momentum: false, precise: true) == nil,
                "A long gesture must not skip multiple columns")
        }
        _ = gesture.consume(delta: 0, time: 1.1, phase: .ended, momentum: false, precise: true)
        for tick in 0...40 {
            precondition(gesture.consume(delta: 15, time: 1.2 + Double(tick) / 50, phase: .unphased, momentum: true, precise: true) == nil)
        }
        precondition(gesture.consume(delta: -9, time: 2.2, phase: .began, momentum: false, precise: true) == .right)
        _ = gesture.consume(delta: 0, time: 2.3, phase: .cancelled, momentum: false, precise: true)
        precondition(gesture.consume(delta: -9, time: 2.4, phase: .began, momentum: false, precise: true) == .right)
        gesture.reset()
        precondition(gesture.consume(delta: 1, time: 3, phase: .unphased, momentum: false, precise: false) == .left)
        precondition(gesture.consume(delta: 3, time: 3.2, phase: .unphased, momentum: false, precise: false) == nil)
        precondition(gesture.consume(delta: -1, time: 3.5, phase: .unphased, momentum: false, precise: false) == .right)
        precondition(gesture.consume(delta: .nan, time: 4, phase: .began, momentum: false, precise: true) == nil)
        var template = Configuration.defaultLayouts(browser: "browser", editor: "editor", teams: "teams")[1].placements
        let moved = ScrollingTemplate.move(&template, index: 1, x: 0.25, y: 0.9)
        precondition(moved == 1 && ScrollingTemplate.columns(template) == [[0, 1], [2]])
        ScrollingTemplate.resize(&template, index: 1, width: 0.73, snap: true)
        precondition(template[0].frame.width == 0.75 && template[1].frame.width == 0.75)
        let separated = ScrollingTemplate.move(&template, index: 1, x: 2, y: 0.2)
        precondition(separated == 2 && template[2].bundleID == "editor" && template[2].scrollColumn == nil)
        precondition(ScrollingTemplate.columns(template).count == 3)
        let reordered = ScrollingTemplate.move(&template, index: 2, x: -0.1, y: 0.2)
        precondition(reordered == 0 && template[0].bundleID == "editor")
        ScrollingTemplate.resize(&template, index: 0, width: 5, snap: false)
        precondition(template[0].frame.width == 1)
        ScrollingTemplate.resize(&template, index: 0, width: -1, snap: false)
        precondition(template[0].frame.width == 0.2)
        let legacyOptions = try JSONDecoder().decode(ScrollingOptions.self, from: Data("{}".utf8))
        precondition(legacyOptions.animationDuration == 0.22)
        var invalidTiming = Configuration.starter
        invalidTiming.layouts[0].scrolling = ScrollingOptions()
        invalidTiming.layouts[0].scrolling?.animationDuration = -0.1
        do { try invalidTiming.validate(); fatalError("Invalid scrolling timing accepted") } catch is ConfigError {}
        var focusState = ScrollingFocus()
        focusState.request(2)
        precondition(focusState.resolve(observed: 1, live: [1,2,3], fallback: 1) == 2)
        focusState.request(3)
        precondition(focusState.resolve(observed: 2, live: [1,2,3], fallback: 2) == 3)
        precondition(focusState.resolve(observed: nil, live: [1,2], fallback: 2) == 2)
        precondition(focusState.requested == nil)
        focusState.request(2); focusState.userInteracted()
        precondition(focusState.resolve(observed: 1, live: [1,2], fallback: 2) == 1)
        precondition(focusState.resolve(observed: nil, live: [], fallback: 1) == nil)
        let screen = Rect(x: -1000, y: 30, width: 1000, height: 800)
        var strip = ScrollingStrip()
        strip.reconcile([1,2,3], width: 0.5)
        precondition(strip.ids == [1,2,3])
        let before = strip.frames(screen: screen, gap: 12, center: false)!
        strip.focus(2)
        strip.reconcile([1,2,3,4], width: 0.5)
        precondition(strip.ids == [1,2,4,3])
        strip.focus(4)
        let after = strip.frames(screen: screen, gap: 12, center: false)!
        precondition(before[1]!.width == after[1]!.width)
        precondition(after[4]!.x >= screen.x && after[4]!.x + after[4]!.width <= screen.x + screen.width)
        strip.group(4, next: false)
        precondition(strip.columns[1].windows == [2,4])
        let grouped = strip.frames(screen: screen, gap: 12, center: false)!
        precondition(grouped[2]!.x == grouped[4]!.x && grouped[2]!.y + grouped[2]!.height < grouped[4]!.y)
        precondition(strip.neighbor(2, direction: .down, wrap: false) == 4)
        strip.resize(4, target: "taller")
        let taller = strip.frames(screen: screen, gap: 12, center: false)!
        precondition(taller[4]!.height > grouped[4]!.height)
        strip.reconcile([1,2,3], width: 0.5)
        precondition(strip.frames(screen: screen, gap: 12, center: false)![2]!.height == 776)
        strip.group(2, next: false); strip.ungroup(2)
        precondition(strip.columns.count == 3 && Set(strip.ids) == Set([1,2,3]))
        strip.swap(2, direction: .right)
        precondition(strip.ids == [1,3,2])
        precondition(strip.neighbor(2, direction: .right, wrap: true) == 1)
        precondition(strip.neighbor(2, direction: .right, wrap: false) == nil)
        let resizedBefore = strip.frames(screen: screen, gap: 12, center: false)![2]!
        var mouseFrame = resizedBefore; mouseFrame.width += 100
        strip.resizeToFrame(2, old: resizedBefore, new: mouseFrame, screen: screen, gap: 12)
        precondition(strip.frames(screen: screen, gap: 12, center: false)![2]!.width > resizedBefore.width)
        precondition(strip.frames(screen: screen, gap: 12, center: false, minimumSizes: [2: Rect(x:0,y:0,width:2000,height:1)]) == nil)
        strip.reconcile([], width: 0.5)
        precondition(strip.ids.isEmpty && strip.focused == nil && strip.offset == 0)
        for count in 1...100 {
            var s = ScrollingStrip(); let ids = Array(1...count)
            s.reconcile(ids, width: 0.5)
            for id in [1, count] {
                s.focus(id)
                let frames = s.frames(screen: screen, gap: 12, center: false)!
                precondition(frames.count == count)
                let focused = frames[id]!
                precondition(focused.x >= screen.x && focused.x + focused.width <= screen.x + screen.width)
                for frame in frames.values {
                    let projected = ScrollingStrip.desktopFrame(frame, screen: screen)
                    precondition(projected.intersectionArea(screen) > 0)
                    precondition(projected.width == frame.width)
                }
            }
        }
        var layout = Layout(name: "Scroll", placements: [])
        layout.scrolling = ScrollingOptions()
        var config = Configuration.starter; config.layouts.append(layout)
        let roundTrip = try Configuration.decode(config.encoded())
        precondition(roundTrip.layouts.last?.scrolling == layout.scrolling)
        let old = Data("{\"name\":\"Legacy\",\"placements\":[]}".utf8)
        let legacy = try JSONDecoder().decode(Layout.self, from: old)
        precondition(legacy.scrolling == nil)
        let display = Display(id:"one",name:"One",builtIn:true,primary:true,frame:screen,usable:screen)
        let windows = (1...4).map { WindowDescriptor(id:$0,bundleID:"app.\($0)",title:"",frame:screen) }
        var session = ScrollingSession()
        let plan = session.plan(layout:layout,windows:windows,displays:[display],gap:12,focused:4)
        precondition(plan.moves.count == 4 && !plan.parked.contains(4))
        // A full-width focused tile must not intersect the parked windows' visible edge.
        var fullWidthLayout = layout
        fullWidthLayout.scrolling?.width = 1
        fullWidthLayout.scrolling?.centerFocus = true
        fullWidthLayout.placements = []
        for focus in 1...4 {
            var fullSession = ScrollingSession()
            let fullPlan = fullSession.plan(layout: fullWidthLayout, windows: windows, displays: [display], gap: 0, focused: focus)
            let visible = fullPlan.moves.first { $0.windowID == focus }!.frame
            for parked in fullPlan.moves where fullPlan.parked.contains(parked.windowID) {
                precondition(visible.intersectionArea(parked.frame) == 0, "Parked windows overlap the focused tile")
            }
        }
        var partialLayout = layout
        partialLayout.scrolling?.width = 0.5
        partialLayout.scrolling?.centerFocus = true
        partialLayout.placements = []
        var partialSession = ScrollingSession()
        let partialPlan = partialSession.plan(layout: partialLayout, windows: windows, displays: [display], gap: 12, focused: 2)
        precondition(partialPlan.visible.contains(1) && partialPlan.visible.contains(3), "Partially visible neighbors must stay above parked windows")
        precondition(!partialPlan.visible.contains(4), "Fully parked windows must stay behind visible neighbors")
        var exclusionLayout = layout
        exclusionLayout.scrolling?.allWindows = true
        exclusionLayout.scrolling?.excludedBundleIDs = ["app.1"]
        var excludedSession = ScrollingSession()
        let exclusionPlan = excludedSession.plan(layout: exclusionLayout, windows: windows, displays: [display], gap: 12, focused: nil)
        precondition(!exclusionPlan.moves.contains { $0.windowID == 1 })
        precondition(exclusionPlan.moves.count == 3)
        let roundtripExcluded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(exclusionLayout))
        precondition(roundtripExcluded.scrolling?.excludedBundleIDs == ["app.1"])
        let motionScreen = Display(id: "motion", name: "Motion", builtIn: false, primary: true,
            frame: Rect(x: 0, y: 0, width: 1000, height: 800), usable: Rect(x: 0, y: 0, width: 1000, height: 800))
        let motion = ScrollingMotion(starts: [1: Rect(x: 100, y: 0, width: 300, height: 800), 2: Rect(x: 420, y: 0, width: 300, height: 800)],
            ends: [1: Rect(x: -220, y: 0, width: 300, height: 800), 2: Rect(x: 100, y: 0, width: 300, height: 800)], screen: motionScreen, displays: [motionScreen])
        for step in 0...20 {
            let first = motion.frame(for: 1, progress: Double(step) / 20)!
            let second = motion.frame(for: 2, progress: Double(step) / 20)!
            precondition(abs(second.x - first.x - first.width - 20) < 0.001, "Columns must translate together")
        }
        let laptop = Display(id:"laptop",name:"MacBook",builtIn:true,primary:true,frame:Rect(x:0,y:0,width:1800,height:1169),usable:Rect(x:0,y:39,width:1800,height:1130))
        // Retarget a partially completed transition. Every window must continue
        // left for repeated Next commands, even when widths and row counts vary.
        var repeatStrip = ScrollingStrip()
        repeatStrip.reconcile(Array(1...8), width: 0.5, groups: [2: 0, 3: 0], widths: [1: 1, 4: 0.33, 6: 0.75])
        let repeatViewport = ScrollingSession.viewport(on: laptop, neighborPreview: 10)
        var current = repeatStrip.frames(screen: repeatViewport, gap: 12, center: true)!
        for target in [2, 4, 5, 6, 7, 8] {
            repeatStrip.focus(target)
            let end = repeatStrip.frames(screen: repeatViewport, gap: 12, center: true)!
            let transition = ScrollingMotion(starts: current, ends: end, screen: laptop, displays: [laptop])
            var previous = current.mapValues { ScrollingSession.project($0, onto: laptop, displays: [laptop]) }
            for tick in 0...20 {
                for id in repeatStrip.ids {
                    let actual = transition.frame(for: id, progress: Double(tick) / 20)!
                    precondition(actual.x <= previous[id]!.x + 0.001, "Repeated Next reversed a window")
                    previous[id] = actual
                }
            }
            current = transition.logicalFrames(progress: 0.35)
        }
        let odyssey = Display(id:"odyssey",name:"Odyssey G95C",builtIn:false,primary:false,frame:Rect(x:1800,y:-750,width:5120,height:1440),usable:Rect(x:1800,y:-750,width:5120,height:1440))
        // Same app on two displays has independent width rules, groups and focus.
        var multi = Layout(name: "Independent", placements: [
            Placement(bundleID: "same.app", display: "built-in", frame: Rect(x: 0, y: 0, width: 1, height: 1)),
            Placement(bundleID: "same.app", display: "external-1", frame: Rect(x: 0, y: 0, width: 0.35, height: 1))])
        multi.scrolling = ScrollingOptions(); multi.scrolling?.display = "all"; multi.scrolling?.centerFocus = true
        let independentTopology = [laptop, odyssey]
        precondition(Set(ScrollingSession.targets(layout: multi, displays: independentTopology).map(\.id)) == Set([laptop.id, odyssey.id]))
        let multiWindows = [
            WindowDescriptor(id: 501, bundleID: "same.app", title: "", frame: Rect(x: 100, y: 100, width: 800, height: 600)),
            WindowDescriptor(id: 502, bundleID: "same.app", title: "", frame: Rect(x: 1900, y: -600, width: 800, height: 600)),
            WindowDescriptor(id: 503, bundleID: "other.app", title: "", frame: Rect(x: 2800, y: -600, width: 800, height: 600))]
        var laptopSession = ScrollingSession(), independentExternal = ScrollingSession()
        let laptopLayout = ScrollingSession.layout(multi, on: laptop, displays: independentTopology)
        let externalLayout = ScrollingSession.layout(multi, on: odyssey, displays: independentTopology)
        let laptopPlan = laptopSession.plan(layout: laptopLayout, windows: multiWindows, displays: independentTopology, gap: 12, focused: 501)
        let externalPlan = independentExternal.plan(layout: externalLayout, windows: multiWindows, displays: independentTopology, gap: 12, focused: 502)
        precondition(laptopSession.strip.ids == [501] && Set(independentExternal.strip.ids) == [502, 503])
        precondition(laptopSession.strip.columns[0].width == 1 && independentExternal.strip.columns[0].width == 0.35)
        independentExternal.strip.focus(503)
        _ = independentExternal.plan(layout: externalLayout, windows: multiWindows.filter { $0.id != 502 }, displays: independentTopology, gap: 12, focused: 503)
        precondition(laptopSession.strip.focused == 501 && independentExternal.strip.ids == [503])
        let combinedMotion = ScrollingMotion(parts: [
            ScrollingMotion(starts: laptopPlan.logicalFrames, ends: laptopPlan.logicalFrames, screen: laptop, displays: independentTopology),
            ScrollingMotion(starts: externalPlan.logicalFrames, ends: externalPlan.logicalFrames, screen: odyssey, displays: independentTopology)])
        for step in 0...20 { precondition(combinedMotion.frame(for: 501, progress: Double(step)/20) == laptopPlan.moves[0].frame) }
        multi.scrolling?.displayModes["uuid:" + laptop.id] = "normal"
        precondition(ScrollingSession.targets(layout: multi, displays: independentTopology).map(\.id) == [odyssey.id])
        multi.scrolling?.displayModes["uuid:" + laptop.id] = "floating"
        precondition(ScrollingSession.mode(on: laptop, layout: multi, displays: independentTopology) == "floating")
        multi.scrolling?.displayExcludedBundleIDs["uuid:" + odyssey.id] = ["same.app"]
        precondition(ScrollingSession.layout(multi, on: laptop, displays: independentTopology).scrolling?.excludedBundleIDs == [])
        precondition(ScrollingSession.layout(multi, on: odyssey, displays: independentTopology).scrolling?.excludedBundleIDs == ["same.app"])
        // Screen-first editing must never reinterpret the primary screen as the selected external.
        var screenFirst = LayoutScreens.emptyLayout(name: "Screen-first")
        screenFirst.fallbackToPrimary = true
        precondition(LayoutScreens.mode(on: laptop, layout: screenFirst, displays: independentTopology) == .floating)
        LayoutScreens.setMode(.horizontal, on: odyssey, layout: &screenFirst, displays: independentTopology)
        precondition(ScrollingSession.targets(layout: screenFirst, displays: independentTopology).map(\.id) == [odyssey.id])
        precondition(LayoutScreens.mode(on: laptop, layout: screenFirst, displays: independentTopology) == .floating)
        precondition(ScrollingSession.targets(layout: screenFirst, displays: [laptop]).isEmpty,
            "A disconnected explicitly chosen Odyssey must never become laptop scrolling")
        LayoutScreens.setMode(.normal, on: laptop, layout: &screenFirst, displays: independentTopology)
        precondition(LayoutScreens.mode(on: odyssey, layout: screenFirst, displays: independentTopology) == .horizontal)
        LayoutScreens.setMode(.floating, on: laptop, layout: &screenFirst, displays: independentTopology)
        precondition(LayoutScreens.mode(on: odyssey, layout: screenFirst, displays: independentTopology) == .horizontal)
        var perScreenConfig = Configuration.starter
        perScreenConfig.monitorProfiles = []
        perScreenConfig.shortcuts = []
        perScreenConfig.layouts = [screenFirst]
        try perScreenConfig.validate()
        let screenFirstDecoded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(screenFirst))
        precondition(screenFirstDecoded == screenFirst)
        var savedApps = Layout(name: "Saved apps", placements: multi.placements)
        savedApps.adaptive = true
        let originalTemplates = savedApps.placements
        LayoutScreens.setMode(.horizontal, on: odyssey, layout: &savedApps, displays: independentTopology)
        precondition(savedApps.placements == originalTemplates, "Mode edits must preserve widths, groups and app rules")
        precondition(LayoutScreens.mode(on: laptop, layout: savedApps, displays: independentTopology) == .adaptive)
        let adaptiveLocal = LayoutScreens.templatePlan(on: laptop, layout: savedApps, windows: multiWindows,
            displays: independentTopology, gap: 12)
        precondition(adaptiveLocal.moves.map(\.windowID) == [501], "Saved apps must not pull the other display's same-app window")
        precondition(adaptiveLocal.moves[0].frame == Rect(x: 0, y: 0, width: 1, height: 1).resolved(in: laptop.usable, gap: 12))
        LayoutScreens.setMode(.fixed, on: laptop, layout: &savedApps, displays: independentTopology)
        let fixedLocal = LayoutScreens.templatePlan(on: laptop, layout: savedApps, windows: multiWindows,
            displays: independentTopology, gap: 12)
        precondition(fixedLocal.moves.map(\.windowID) == [501])
        precondition(LayoutScreens.templatePlan(on: odyssey, layout: savedApps, windows: multiWindows, displays: independentTopology, gap: 12).moves.isEmpty)
        LayoutScreens.setMode(.floating, on: laptop, layout: &savedApps, displays: independentTopology)
        precondition(LayoutScreens.templatePlan(on: laptop, layout: savedApps, windows: multiWindows, displays: independentTopology, gap: 12).moves.isEmpty)
        var disconnected = Layout(name: "Portable", placements: [Placement(bundleID: "same.app", display: "external-2", frame: Rect(x: 0, y: 0, width: 0.5, height: 1))])
        LayoutScreens.setMode(.horizontal, on: laptop, layout: &disconnected, displays: [laptop])
        precondition(disconnected.scrolling?.displayModes["external-2"] == "fixed")
        perScreenConfig.layouts = [savedApps, disconnected]
        try perScreenConfig.validate()
        print("Passed: screen-first mode changes, external targeting without primary fallback, legacy preservation, disconnected roles, local fixed/adaptive matching and persistence.")
        // Explicit Apply and Preview route named apps to their saved displays;
        // unlisted apps keep their current display and normal navigation stays local.
        var assignedLayout = LayoutScreens.emptyLayout(name: "Odyssey apps")
        LayoutScreens.setMode(.horizontal, on: odyssey, layout: &assignedLayout, displays: independentTopology)
        LayoutScreens.setMode(.normal, on: laptop, layout: &assignedLayout, displays: independentTopology)
        assignedLayout.placements = (1...5).map {
            Placement(bundleID: "named.\($0)", display: "external-1", frame: Rect(x: 0, y: 0, width: Double($0) / 10 + 0.2, height: 1))
        }
        let allOnLaptop = (1...7).map {
            WindowDescriptor(id: 700 + $0, bundleID: "named.\($0)", title: "", frame: Rect(x: 100, y: 100, width: 800, height: 600))
        }
        let assignment = LayoutAssignments.plan(assignedLayout, windows: allOnLaptop, displays: independentTopology)
        precondition(Set(assignment.destinations.keys) == Set(701...705))
        precondition(Set(assignment.destinations.values) == [odyssey.id])
        let previewMembership = LayoutAssignments.projected(allOnLaptop, destinations: assignment.destinations, displays: independentTopology)
        let previewRules = LayoutAssignments.localized(assignedLayout, windows: previewMembership, displays: independentTopology, matches: assignment.matches)
        var previewStrip = ScrollingSession()
        let assignedPreview = previewStrip.plan(layout: ScrollingSession.layout(previewRules, on: odyssey, displays: independentTopology),
            windows: previewMembership, displays: independentTopology, gap: 12, focused: nil)
        precondition(Set(assignedPreview.moves.map(\.windowID)) == Set(701...705))
        for move in assignedPreview.moves {
            precondition(Displays.containing(move.frame, in: independentTopology)?.id == odyssey.id)
            precondition(move.frame.intersectionArea(laptop.frame) == 0)
        }
        precondition(previewMembership.filter { Displays.containing($0.frame, in: independentTopology)?.id == laptop.id }.map(\.id) == [706,707])
        let appliedMembership = allOnLaptop.map { window -> WindowDescriptor in
            var updated = window
            if let move = assignedPreview.moves.first(where: { $0.windowID == window.id }) { updated.frame = move.frame }
            return updated
        }
        // Reflow without new assignments uses the real display and cannot pull back a manually moved window.
        var manuallyMoved = appliedMembership
        manuallyMoved[0].frame = allOnLaptop[0].frame
        let localReflow = previewStrip.plan(layout: ScrollingSession.layout(previewRules, on: odyssey, displays: independentTopology),
            windows: manuallyMoved, displays: independentTopology, gap: 12, focused: nil)
        precondition(!localReflow.moves.contains(where: { $0.windowID == 701 }))
        // Same-app rules on both screens reserve local windows regardless of rule order.
        var twoScreens = assignedLayout
        twoScreens.placements = multi.placements.reversed()
        twoScreens.scrolling?.displayModes["uuid:" + laptop.id] = "horizontal"
        let localAssignment = LayoutAssignments.plan(twoScreens, windows: multiWindows, displays: independentTopology)
        precondition(localAssignment.destinations[501] == laptop.id && localAssignment.destinations[502] == odyssey.id)
        // Two same-app windows starting on one screen fill two different destinations once each.
        var twoAway = multiWindows.filter { $0.bundleID == "same.app" }
        twoAway[1].frame = twoAway[0].frame
        let twoAwayAssignment = LayoutAssignments.plan(twoScreens, windows: twoAway, displays: independentTopology)
        precondition(twoAwayAssignment.destinations[501] == laptop.id && twoAwayAssignment.destinations[502] == odyssey.id)
        // Indexed and title rules retain their concrete windows after screen-local indices change.
        var indexedLayout = assignedLayout
        var indexedRule = Placement(bundleID: "same.app", display: "external-1", frame: Rect(x: 0, y: 0, width: 0.75, height: 1))
        indexedRule.windowIndex = 1
        indexedLayout.placements = [indexedRule]
        let indexedAssignment = LayoutAssignments.plan(indexedLayout, windows: twoAway, displays: independentTopology)
        precondition(indexedAssignment.matches[0] == 502 && indexedAssignment.destinations[501] == nil)
        let indexedMembership = LayoutAssignments.projected(twoAway, destinations: indexedAssignment.destinations, displays: independentTopology)
        let indexedRules = LayoutAssignments.localized(indexedLayout, windows: indexedMembership, displays: independentTopology, matches: indexedAssignment.matches)
        precondition(indexedRules.placements[0].windowIndex == 0)
        var indexedStrip = ScrollingSession()
        _ = indexedStrip.plan(layout: ScrollingSession.layout(indexedRules, on: odyssey, displays: independentTopology), windows: indexedMembership, displays: independentTopology, gap: 12, focused: nil)
        precondition(indexedStrip.strip.ids == [502] && indexedStrip.strip.columns[0].width == 0.75)
        var firstRule = indexedRule; firstRule.windowIndex = 0
        indexedLayout.placements = [firstRule, indexedRule]
        let bothIndexed = LayoutAssignments.plan(indexedLayout, windows: twoAway, displays: independentTopology)
        precondition(bothIndexed.matches == [0:501,1:502])
        indexedLayout.placements = [firstRule, firstRule]
        let duplicateAssignment = LayoutAssignments.plan(indexedLayout, windows: twoAway, displays: independentTopology)
        precondition(duplicateAssignment.destinations.count == 1 && !duplicateAssignment.messages.isEmpty)
        indexedLayout.placements = [firstRule]
        indexedLayout.placements[0].titleContains = "second"
        twoAway[0].title = "first"; twoAway[1].title = "second"
        precondition(LayoutAssignments.plan(indexedLayout, windows: twoAway, displays: independentTopology).matches == [0:502])
        // Exclusions, missing screens, unchanged screens and impossible parking never cause transfers.
        assignedLayout.scrolling?.displayExcludedBundleIDs["uuid:" + odyssey.id] = ["named.1"]
        precondition(LayoutAssignments.plan(assignedLayout, windows: allOnLaptop, displays: independentTopology).destinations[701] == nil)
        precondition(LayoutAssignments.plan(assignedLayout, windows: allOnLaptop, displays: [laptop]).destinations.isEmpty)
        LayoutScreens.setMode(.floating, on: odyssey, layout: &assignedLayout, displays: independentTopology)
        precondition(LayoutAssignments.plan(assignedLayout, windows: allOnLaptop, displays: independentTopology).destinations.isEmpty)
        // Fixed and adaptive screen modes use exactly the same assignment stage.
        for mode in [LayoutScreenMode.fixed, .adaptive] {
            LayoutScreens.setMode(mode, on: odyssey, layout: &indexedLayout, displays: independentTopology)
            let assignment = LayoutAssignments.plan(indexedLayout, windows: twoAway, displays: independentTopology)
            let membership = LayoutAssignments.projected(twoAway, destinations: assignment.destinations, displays: independentTopology)
            let rules = LayoutAssignments.localized(indexedLayout, windows: membership, displays: independentTopology, matches: assignment.matches)
            let plan = LayoutScreens.templatePlan(on: odyssey, layout: rules, windows: membership, displays: independentTopology, gap: 12)
            precondition(plan.moves.map(\.windowID) == [502] && Displays.containing(plan.moves[0].frame, in: independentTopology)?.id == odyssey.id)
        }
        print("Passed: saved-screen assignment for seven apps, preview/apply geometry, unlisted-window isolation, same-app multi-screen rules, indexed/title matches, duplicates, exclusions and fixed/adaptive routing.")
        let multiDecoded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(multi))
        precondition(multiDecoded == multi)
        var groupedScreens = multi.placements
        groupedScreens[0].scrollColumn = 0; groupedScreens[1].scrollColumn = 0
        precondition(ScrollingTemplate.columns(groupedScreens) == [[0], [1]])
        ScrollingTemplate.resize(&groupedScreens, index: 0, width: 0.7, snap: false)
        precondition(groupedScreens[1].frame.width == 0.35)
        precondition(ScrollingTemplate.frames(groupedScreens)[0]?.x == 0 && ScrollingTemplate.frames(groupedScreens)[1]?.x == 0)
        // A full-width middle column still leaves real neighbors on both free edges.
        for width in [0.2, 0.33, 0.5, 0.75, 1.0] {
            var peekLayout = fullWidthLayout
            peekLayout.scrolling?.width = width
            peekLayout.scrolling?.neighborPreview = 120
            var session = ScrollingSession()
            let peekPlan = session.plan(layout: peekLayout, windows: windows, displays: [display], gap: 12, focused: 2)
            for neighbor in [1, 3] {
                let frame = peekPlan.moves.first { $0.windowID == neighbor }!.frame
                precondition(frame.intersectionArea(display.usable) / frame.height >= 120, "Neighbor disappeared beside width \(width)")
            }
            let focused = peekPlan.moves.first { $0.windowID == 2 }!.frame
            precondition(peekPlan.moves.filter { $0.windowID != 2 }.allSatisfy { focused.intersectionArea($0.frame) == 0 })
        }
        // Retargeting an interrupted animation must start exactly at its last
        // logical frame instead of jumping to the cancelled command's endpoint.
        let interrupted = motion.logicalFrames(progress: 0.35)
        let reversal = ScrollingMotion(starts: interrupted, ends: motion.starts, screen: motionScreen, displays: [motionScreen])
        for id in [1, 2] {
            precondition(reversal.frame(for: id, progress: 0) == motion.frame(for: id, progress: 0.35))
            precondition(reversal.frame(for: id, progress: 1) == ScrollingSession.project(motion.starts[id]!, onto: motionScreen, displays: [motionScreen]))
        }
        // The laptop begins below the upper row. Both rows must still use the
        // same safe parking edge and stay aligned throughout each transition.
        let top = Rect(x: 600, y: -738, width: 2500, height: 687)
        let bottom = Rect(x: 600, y: -39, width: 2500, height: 687)
        let topology = [laptop, odyssey]
        precondition(!ScrollingSession.supportsContinuousMotion(on: odyssey, displays: topology))
        var below = laptop
        below.frame = Rect(x: 3400, y: 690, width: 1800, height: 1169)
        below.usable = Rect(x: 3400, y: 729, width: 1800, height: 1130)
        precondition(ScrollingSession.supportsContinuousMotion(on: odyssey, displays: [below, odyssey]))
        // Native projections move monotonically in the requested direction when
        // the display has both free edges, even after an interrupted transition.
        for direction in [-1.0, 1.0] {
            let a = Rect(x: odyssey.usable.x + 100, y: odyssey.usable.y, width: 2500, height: 1386)
            var b = a; b.x += direction * 7000
            let stepMotion = ScrollingMotion(starts: [1: a], ends: [1: b], screen: odyssey, displays: [below, odyssey])
            var previous = stepMotion.frame(for: 1, progress: 0)!.x
            for step in 1...100 {
                let next = stepMotion.frame(for: 1, progress: Double(step) / 100)!.x
                precondition((next - previous) * direction >= -0.0001)
                previous = next
            }
        }
        for x in stride(from: -4000.0, through: 8000.0, by: 100) {
            var a = top; var b = bottom; a.x = x; b.x = x
            let pa = ScrollingSession.project(a, onto: odyssey, displays: topology)
            let pb = ScrollingSession.project(b, onto: odyssey, displays: topology)
            precondition(pa.x == pb.x, "Stacked windows must not arrive from opposite edges")
            precondition(pa.intersectionArea(laptop.frame) == 0 && pb.intersectionArea(laptop.frame) == 0)
        }
        layout.scrolling?.display = "external-1"
        var externalSession = ScrollingSession()
        let externalWindows = windows.map { WindowDescriptor(id: $0.id, bundleID: $0.bundleID, title: "", frame: odyssey.usable) }
        let laptopWindow = WindowDescriptor(id: 90, bundleID: "app.1", title: "", frame: laptop.usable)
        for focus in 1...4 {
            let plan = externalSession.plan(layout:layout,windows:externalWindows + [laptopWindow],displays:[laptop,odyssey],gap:12,focused:focus)
            precondition(plan.moves.count == 4)
            for move in plan.moves {
                precondition(move.frame.intersectionArea(laptop.frame) == 0)
                precondition(move.frame.intersectionArea(odyssey.frame) > 0)
            }
        }
        precondition(!externalSession.strip.ids.contains(90), "A matching app on the laptop must not be pulled into the strip")
        var migrated = externalWindows
        migrated[0].frame = laptop.usable
        let afterMigration = externalSession.plan(layout: layout, windows: migrated + [laptopWindow], displays: [laptop, odyssey], gap: 12, focused: nil)
        precondition(afterMigration.moves.count == 3 && !externalSession.strip.ids.contains(1))
        let laptopOnly = externalSession.plan(layout: layout, windows: [laptopWindow], displays: [laptop, odyssey], gap: 12, focused: nil)
        precondition(laptopOnly.moves.isEmpty && externalSession.strip.focused == nil)
        let afterReopening = externalSession.plan(layout: layout, windows: externalWindows + [laptopWindow], displays: [laptop, odyssey], gap: 12, focused: 3)
        precondition(afterReopening.moves.count == 4 && externalSession.strip.focused == 3)
        precondition(legacyOptions.tileOtherDisplays)
        var unchangedOthers = layout; unchangedOthers.scrolling?.tileOtherDisplays = false
        let decodedOthers = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(unchangedOthers))
        precondition(decodedOthers.scrolling?.tileOtherDisplays == false)
        let right = Display(id:"right",name:"Right",builtIn:false,primary:false,frame:Rect(x:6920,y:-750,width:1920,height:1440),usable:Rect(x:6920,y:-750,width:1920,height:1440))
        precondition(ScrollingSession.target(layout:layout,displays:[laptop,odyssey,right]) == nil)
        layout.scrolling?.display = "primary"
        layout.scrolling?.allWindows = false
        precondition(ScrollingSession().strip.ids.isEmpty)
        var selectedSession = ScrollingSession()
        precondition(selectedSession.plan(layout:layout,windows:windows,displays:[display],gap:12,focused:4).moves.isEmpty)
        for width in [1800.0, 5120.0] {
            let wide = Rect(x: 0, y: 25, width: width, height: 1415)
            var s = ScrollingStrip()
            s.reconcile(Array(1...20), width: 1.0 / 3, groups: [1: 0, 2: 0])
            for id in 1...20 {
                s.focus(id)
                let frames = s.frames(screen: wide, gap: 12, center: true)!
                precondition(frames[id]!.x >= wide.x && frames[id]!.x + frames[id]!.width <= wide.x + wide.width)
                precondition(abs(frames[id]!.x + frames[id]!.width / 2 - (wide.x + wide.width / 2)) < 0.001)
            }
        }
        var groupedLayout = layout
        groupedLayout.placements = [Placement(bundleID: "app.1", display: "primary", frame: Rect(x:0,y:0,width:0.5,height:1)), Placement(bundleID: "app.2", display: "primary", frame: Rect(x:0,y:0,width:0.5,height:1))]
        groupedLayout.placements[0].scrollColumn = 0; groupedLayout.placements[1].scrollColumn = 0
        var constrained = ScrollingSession()
        var stacked = groupedLayout
        stacked.placements[0].display = "external-2"
        stacked.placements[1].display = "external-2"
        stacked.placements[0].frame.width = 1
        stacked.placements[1].frame.width = 1
        var stackedSession = ScrollingSession()
        let stackedPlan = stackedSession.plan(layout: stacked, windows: windows, displays: [display], gap: 12, focused: 1)
        precondition(stackedPlan.moves.count == 2 && stackedSession.strip.columns.count == 1)
        precondition(stackedPlan.moves.allSatisfy { abs($0.frame.width - (ScrollingSession.viewport(on: display).width - 24)) < 1 })
        precondition(stackedPlan.moves[0].frame.intersectionArea(stackedPlan.moves[1].frame) == 0)
        var appWidthLayout = stacked
        appWidthLayout.scrolling?.allWindows = true
        appWidthLayout.placements = [stacked.placements[0]]
        let additionalWindow = WindowDescriptor(id: 99, bundleID: "app.1", title: "second", frame: screen)
        var appWidthSession = ScrollingSession()
        let appWidths = appWidthSession.plan(layout: appWidthLayout, windows: windows + [additionalWindow], displays: [display], gap: 12, focused: 99)
        precondition(appWidths.moves.first(where: { $0.windowID == 99 })?.frame.width == ScrollingSession.viewport(on: display).width - 24)
        let fallback = constrained.plan(layout:groupedLayout,windows:windows,displays:[display],gap:12,focused:1,
            minimumSizes:[1:Rect(x:0,y:0,width:1,height:600),2:Rect(x:0,y:0,width:1,height:600)])
        precondition(fallback.moves.count == 2 && constrained.strip.columns.count == 2 && !fallback.messages.isEmpty)
        var dragStrip = ScrollingStrip()
        dragStrip.reconcile([1,2,3], width: 0.5)
        let dropScreen = Rect(x: 0, y: 0, width: 2000, height: 1200)
        let oldDrag = Rect(x: 1000, y: 0, width: 800, height: 1100)
        let movedDrag = Rect(x: 100, y: 800, width: 800, height: 1100)
        let targetFrame = Rect(x: 0, y: 0, width: 800, height: 1100)
        precondition(!dragStrip.dropBelow(2, old: oldDrag, new: movedDrag, pointerX: 400, pointerY: 200, frames: [1:targetFrame], screen: dropScreen))
        precondition(dragStrip.dropBelow(2, old: oldDrag, new: movedDrag, pointerX: 400, pointerY: 850, frames: [1:targetFrame], screen: dropScreen))
        precondition(dragStrip.columns[0].windows == [1,2])
        dragStrip.stack(3, below: 1)
        precondition(dragStrip.columns[0].windows == [1,3,2] && Set(dragStrip.ids).count == 3)
        dragStrip.stack(1, below: 2)
        precondition(dragStrip.columns[0].windows == [3,2,1])
        var burst = ScrollingStrip(); burst.reconcile([1,2], width:0.5); burst.focus(1)
        burst.reconcile([1,2,3,4,5], width:0.5)
        precondition(burst.ids == [1,3,4,5,2])
        var closing = ScrollingStrip(); closing.reconcile([1,2,3,4,5], width: 0.5)
        closing.focus(3); closing.reconcile([1,2,4,5], width: 0.5)
        precondition(closing.focused == 4)
        precondition(closing.neighbor(closing.focused!, direction: .left, wrap: false) == 2)
        precondition(closing.neighbor(closing.focused!, direction: .right, wrap: false) == 5)
        closing.focus(5); closing.reconcile([1,2,4], width: 0.5)
        precondition(closing.focused == 4 && closing.neighbor(4, direction: .left, wrap: false) == 2)
        print("Passed: one step per gesture, momentum rejection, new gestures, wheel bursts and repeated interrupted directional motion.")
        print("Passed: independent display membership, app widths, grouping, focus, display modes, composed motion and full-width neighbor space.")
        print("Passed: delayed focus acknowledgements, explicit focus changes, focused-window closure recovery.")
        print("Passed: scrolling insertion, stable widths, viewport focus, grouping, close/reflow, ungroup, reorder, wrap, keyboard/mouse resizing, minimum sizes, 1–100 windows, visible parking, legacy decoding, settings round-trip, all/selected apps and multi-display guard.")
    }
}
