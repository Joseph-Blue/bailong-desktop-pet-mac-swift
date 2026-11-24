import AppKit

final class ActivitySettingsPage {
    private let form:SettingsForm, catalog:Catalog?
    private let onPreview:(Clip) -> Void
    private(set) var viewport:SettingsRowViewport?
    private var preferences:PetPreferences {form.preferences}
    init(form:SettingsForm,catalog:Catalog?,onPreview:@escaping (Clip) -> Void) {
        self.form = form; self.catalog = catalog; self.onPreview = onPreview
    }
    func reset() {viewport = nil}
    func render() {
        let gestureRows = PetGestureSetting.all.map { gesture in
            form.choice(gesture.title, gesture.key, PetGestureSetting.actions, width:260, help:gesture.help)
        }
        let dragTilt = form.toggle(L10n.text(.settings,"activity.dragTiltEnabled.title"),"dragTiltEnabled",
                                   detail:L10n.text(.settings,"activity.dragTiltEnabled.detail"),requires:["bubbleMotion"])
        let dragTiltIntensity = form.slider(L10n.text(.settings,"activity.dragTiltIntensity.title"),"dragTiltIntensity",
            range:PetPreferences.dragTiltIntensityRange,step:5,suffix:"%",detail:L10n.text(.settings,"activity.dragTiltIntensity.detail"),
            requires:["bubbleMotion","dragTiltEnabled"])
        form.group(PetGestureSetting.group,gestureRows+[dragTilt,dragTiltIntensity],symbol:"computermouse")
        form.group(L10n.text(.settings,"activity.render.text"),[
            form.toggle(L10n.text(.settings,"activity.sideDockEnabled.title"),"sideDockEnabled"),
            form.slider(L10n.text(.settings,"activity.sideExposurePercent.title"),"sideExposurePercent",range:40...85,step:5,suffix:"%",requires:["sideDockEnabled"]),
            form.toggle(L10n.text(.settings,"activity.notchDockEnabled.title"),"notchDockEnabled",detail:L10n.text(.settings,"activity.notchDockEnabled.detail"),symbol:"macbook.gen2"),
            form.slider(L10n.text(.settings,"activity.notchExposurePercent.title"),"notchExposurePercent",range:40...85,step:5,suffix:"%",requires:["notchDockEnabled"]),
            form.toggle(L10n.text(.settings,"activity.windowDockEnabled.title"),"windowDockEnabled",detail:L10n.text(.settings,"activity.windowDockEnabled.detail")),
            form.choice(L10n.text(.settings,"activity.windowDockModifier.title"),WindowDockModifier.key,WindowDockModifier.options,requires:["windowDockEnabled"])],symbol:"rectangle.inset.filled")
        form.group(L10n.text(.settings,"activity.render.text.2"),[
            form.slider(L10n.text(.settings,"activity.leisureInterval.title"),"leisureInterval",range:5...180,suffix:L10n.text(.settings,"activity.leisureInterval.suffix"),detail:L10n.text(.settings,"activity.leisureInterval.detail")),
            form.toggle(L10n.text(.settings,"activity.autoMove.title"),"autoMove"),form.choice(L10n.text(.settings,"activity.movementRange.title"),"movementRange",[("still",L10n.text(.settings,"activity.movementRange.option.still")),("nearby",L10n.text(.settings,"activity.movementRange.option.nearby")),("screen",L10n.text(.settings,"activity.movementRange.option.screen"))],requires:["autoMove"]),form.toggle(L10n.text(.settings,"activity.avoidRepeat.title"),"avoidRepeat",detail:L10n.text(.settings,"activity.avoidRepeat.detail")),
            form.slider(L10n.text(.settings,"activity.playbackSpeed.title"),"playbackSpeed",range:0.75...1.5,step:0.05,suffix:"×",detail:L10n.text(.settings,"activity.playbackSpeed.detail"))],symbol:"figure.walk.motion")
        form.group(L10n.text(.settings,"activity.render.text.3"),[form.toggle(L10n.text(.settings,"activity.taskOpening.title"),"taskOpening"),form.toggle(L10n.text(.settings,"activity.taskCelebration.title"),"taskCelebration")],symbol:"checklist")
        guard let catalog else {return}
        var rows = [ActivityActionRow]()
        let sizingForm = SettingsForm(content:NSStackView(),preferences:preferences,window:form.window)
        let weightHeight = sizingForm.animationWeight(catalog.idle).fittingSize.height
        for (title,clips,weighted) in Self.groups(catalog) {
            form.group(title,clips.map {clip in
                let row = ActivityActionRow(title:clip.title,weightHeight:weighted ? weightHeight : 0) { [preferences,onPreview] window in
                    let form = SettingsForm(content:NSStackView(),preferences:preferences,window:window)
                    let speed = form.popupControl(clip.title+L10n.text(.settings,"activity.speed"),options:Self.speedOptions,value:String(preferences.clipSpeed(clip.id)),width:100) {
                        preferences.setSpeed(Double($0)!,for:clip.id)
                    }
                    let caption = NSTextField(labelWithString:L10n.text(.settings,"activity.caption"))
                    caption.textColor = .secondaryLabelColor
                    let playback = form.content
                    playback.orientation = .horizontal; playback.alignment = .centerY; playback.spacing = 8
                    playback.addArrangedSubview(caption); playback.addArrangedSubview(speed)
                    playback.addArrangedSubview(form.animationPreviewButton(clip.title) {onPreview(clip)})
                    return (form,weighted ? form.animationWeight(clip) : nil)
                }
                rows.append(row)
                return form.searchable(row,title:clip.id)
            },symbol:"film")
        }
        if let scroll = form.content.enclosingScrollView {
            viewport = SettingsRowViewport(rows:rows,scroll:scroll)
        }
    }
    private static let speedOptions = PetPreferences.clipSpeedOptions.map {speed in (String(speed),speed == 1 ? L10n.text(.settings,"activity.render.text.4") : String(speed)+"×")}
    private static func groups(_ catalog:Catalog) -> [(String,[Clip],Bool)] {
        [
            (L10n.text(.settings,"activity.groups.text"),catalog.idles+catalog.extras,true),
            (L10n.text(.settings,"activity.groups.text.2"),catalog.variants,true),
            (L10n.text(.settings,"activity.groups.text.3"),catalog.work,true),
            (L10n.text(.settings,"activity.groups.text.4"),catalog.movementAnimationsForDisplay,true),
            (L10n.text(.settings,"activity.groups.text.5"),[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation],false)
        ]
    }
    static func items(catalog:Catalog?) -> [SettingsListItem] {
        guard let catalog else {return []}
        return groups(catalog).flatMap { title,clips,weighted in
            clips.map {.init(group:title,title:$0.title,kind:.animation($0,weighted:weighted),keywords:L10n.text(.settings,"activity.items.keywords")+(weighted ? L10n.text(.settings,"activity.items.text") : ""))}
        }
    }
}
