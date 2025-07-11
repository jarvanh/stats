//
//  popup.swift
//  Disk
//
//  Created by Serhiy Mytrovtsiy on 11/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private var readColorState: SColor = .secondBlue
    private var readColor: NSColor { self.readColorState.additional as? NSColor ?? NSColor.systemRed }
    private var writeColorState: SColor = .secondRed
    private var writeColor: NSColor { self.writeColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var reverseOrderState: Bool = false
    
    private var disks: NSStackView = {
        let view = NSStackView()
        view.spacing = Constants.Popup.margins
        view.orientation = .vertical
        return view
    }()
    
    private var processesInitialized: Bool = false
    
    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }
    private var processesHeight: CGFloat {
        (22*CGFloat(self.numberOfProcesses)) + (self.numberOfProcesses == 0 ? 0 : Constants.Popup.separatorHeight + 22)
    }
    private var processes: ProcessesView? = nil
    private var processesView: NSView? = nil
    
    private let settingsSection = PreferencesSection(label: localizedString("Drives"))
    private var lastList: [String] = []
    
    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.readColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_readColor", defaultValue: self.readColorState.key))
        self.writeColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_writeColor", defaultValue: self.writeColorState.key))
        self.reverseOrderState = Store.shared.bool(key: "\(self.title)_reverseOrder", defaultValue: self.reverseOrderState)
        
        self.orientation = .vertical
        self.distribution = .fill
        self.spacing = 0
        
        self.addArrangedSubview(self.disks)
        self.addArrangedSubview(self.initProcesses())
        
        self.recalculateHeight()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func recalculateHeight() {
        var h: CGFloat = 0
        h += self.disks.subviews.map({ $0.frame.height + self.disks.spacing }).reduce(0, +) - self.disks.spacing
        h += self.processesHeight
        if h > 0 && self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    private func initProcesses() -> NSView {
        if self.numberOfProcesses == 0 {
            let v = NSView()
            self.processesView = v
            return v
        }
        
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.processesHeight))
        let separator = separatorView(localizedString("Top processes"), origin: NSPoint(x: 0, y: self.processesHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: ProcessesView = ProcessesView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y),
            values: [(localizedString("Read"), self.readColor), (localizedString("Write"), self.writeColor)],
            n: self.numberOfProcesses
        )
        self.processes = container
        view.addSubview(separator)
        view.addSubview(container)
        self.processesView = view
        return view
    }
    
    // MARK: - callbacks
    
    internal func capacityCallback(_ value: Disks) {
        defer {
            let h = self.disks.subviews.map({ $0.bounds.height + self.disks.spacing }).reduce(0, +) - self.disks.spacing
            if h > 0 && self.disks.frame.size.height != h {
                self.disks.setFrameSize(NSSize(width: self.frame.width, height: h))
                self.recalculateHeight()
            } else if h < 0 && self.disks.frame.size.height != 0 {
                self.disks.setFrameSize(NSSize(width: self.frame.width, height: 0))
                self.recalculateHeight()
            }
            self.lastList = value.array.compactMap{ $0.uuid }
        }
        
        if self.settingsSection.contains("empty_view") {
            self.settingsSection.delete("empty_view")
        }
        
        self.lastList.filter { !value.map { $0.uuid }.contains($0) }.forEach { self.settingsSection.delete($0) }
        value.forEach { (drive: drive) in
            if !self.settingsSection.contains(drive.uuid) {
                let btn = switchView(
                    action: #selector(self.toggleDisk),
                    state: drive.popupState
                )
                btn.identifier = NSUserInterfaceItemIdentifier(drive.uuid)
                self.settingsSection.add(PreferencesRow(drive.mediaName, id: drive.uuid, component: btn))
            }
        }
        
        self.disks.subviews.filter{ $0 is DiskView }.map{ $0 as! DiskView }.forEach { (v: DiskView) in
            if !value.array.filter({ $0.popupState }).map({$0.uuid}).contains(v.uuid) {
                v.removeFromSuperview()
            }
        }
        value.array.filter({ $0.popupState }).forEach { (drive: drive) in
            if let view = self.disks.subviews.filter({ $0 is DiskView }).map({ $0 as! DiskView }).first(where: { $0.uuid == drive.uuid }) {
                view.update(free: drive.free, smart: drive.smart)
            } else {
                self.disks.addArrangedSubview(DiskView(
                    width: Constants.Popup.width,
                    uuid: drive.uuid,
                    name: drive.mediaName,
                    size: drive.size,
                    free: drive.free,
                    path: drive.path,
                    smart: drive.smart,
                    resize: self.recalculateHeight
                ))
            }
        }
    }
    
    internal func activityCallback(_ value: Disks) {
        let views = self.disks.subviews.filter{ $0 is DiskView }.map{ $0 as! DiskView }
        value.reversed().forEach { (drive: drive) in
            if let view = views.first(where: { $0.name == drive.mediaName }) {
                view.updateStats(stats: drive.activity)
            }
        }
    }
    
    internal func processCallback(_ list: [Disk_process]) {
        DispatchQueue.main.async(execute: {
            if !(self.window?.isVisible ?? false) && self.processesInitialized {
                return
            }
            let list = list.map{ $0 }
            if list.count != self.processes?.count { self.processes?.clear("-") }
            
            for i in 0..<list.count {
                let process = list[i]
                let write = Units(bytes: Int64(process.write)).getReadableSpeed(base: process.base)
                let read = Units(bytes: Int64(process.read)).getReadableSpeed(base: process.base)
                self.processes?.set(i, process, [read, write])
            }
            
            self.processesInitialized = true
        })
    }
    
    internal func numberOfProcessesUpdated() {
        if self.processes?.count == self.numberOfProcesses { return }
        
        DispatchQueue.main.async(execute: {
            self.processesView?.removeFromSuperview()
            self.processesView = nil
            self.processes = nil
            self.addArrangedSubview(self.initProcesses())
            self.processesInitialized = false
            self.recalculateHeight()
        })
    }
    
    // MARK: - Settings
    
    public override func settings() -> NSView? {
        let view = SettingsContainerView()
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Write color"), component: selectView(
                action: #selector(self.toggleWriteColor),
                items: SColor.allColors,
                selected: self.writeColorState.key
            )),
            PreferencesRow(localizedString("Read color"), component: selectView(
                action: #selector(self.toggleReadColor),
                items: SColor.allColors,
                selected: self.readColorState.key
            ))
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Reverse order"), component: switchView(
                action: #selector(self.toggleReverseOrder),
                state: self.reverseOrderState
            ))
        ]))
        
        let empty = NSView()
        empty.identifier = NSUserInterfaceItemIdentifier("empty_view")
        self.settingsSection.add(empty)
        view.addArrangedSubview(self.settingsSection)
        
        return view
    }
    
    @objc private func toggleWriteColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let newValue = SColor.allColors.first(where: { $0.key == key }) else {
            return
        }
        self.writeColorState = newValue
        Store.shared.set(key: "\(self.title)_writeColor", value: key)
        if let color = newValue.additional as? NSColor {
            self.processes?.setColor(1, color)
            for view in self.disks.subviews.filter({ $0 is DiskView }).map({ $0 as! DiskView }) {
                view.setChartColor(write: color)
            }
        }
    }
    @objc private func toggleReadColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let newValue = SColor.allColors.first(where: { $0.key == key }) else {
            return
        }
        self.readColorState = newValue
        Store.shared.set(key: "\(self.title)_readColor", value: key)
        if let color = newValue.additional as? NSColor {
            self.processes?.setColor(0, color)
            for view in self.disks.subviews.filter({ $0 is DiskView }).map({ $0 as! DiskView }) {
                view.setChartColor(read: color)
            }
        }
    }
    @objc private func toggleReverseOrder(_ sender: NSControl) {
        self.reverseOrderState = controlState(sender)
        for view in self.disks.subviews.filter({ $0 is DiskView }).map({ $0 as! DiskView }) {
            view.setChartReverseOrder(self.reverseOrderState)
        }
        Store.shared.set(key: "\(self.title)_reverseOrder", value: self.reverseOrderState)
        self.display()
    }
    @objc private func toggleDisk(_ sender: NSControl) {
        guard let id = sender.identifier else { return }
        Store.shared.set(key: "\(self.title)_\(id.rawValue)_popup", value: controlState(sender))
    }
}

internal class DiskView: NSStackView {
    internal var sizeCallback: (() -> Void) = {}
    
    public var name: String
    public var uuid: String
    private let width: CGFloat
    
    private var nameView: NameView
    private var chartView: ChartView
    private var barView: BarView
    private var legendView: LegendView
    private var detailsView: DetailsView
    
    private var detailsState: Bool {
        get { Store.shared.bool(key: "\(self.uuid)_details", defaultValue: false) }
        set { Store.shared.set(key: "\(self.uuid)_details", value: newValue) }
    }
    
    init(width: CGFloat, uuid: String = "", name: String = "", size: Int64 = 1, free: Int64 = 1, path: URL? = nil, smart: smart_t? = nil, resize: @escaping () -> Void) {
        self.sizeCallback = resize
        self.uuid = uuid
        self.name = name
        self.width = width
        let innerWidth: CGFloat = width - (Constants.Popup.margins * 2)
        self.nameView = NameView(width: innerWidth, name: name, size: size, free: free, path: path)
        self.chartView = ChartView(width: innerWidth)
        self.barView = BarView(width: innerWidth, size: size, free: free)
        self.legendView = LegendView(width: innerWidth, id: "\(name)_\(path?.absoluteString ?? "")", size: size, free: free)
        self.detailsView = DetailsView(width: innerWidth, id: "\(name)_\(path?.absoluteString ?? "")", smart: smart)
        
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        
        self.widthAnchor.constraint(equalToConstant: width).isActive = true
        self.orientation = .vertical
        self.distribution = .fillProportionally
        self.spacing = 5
        self.edgeInsets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        self.wantsLayer = true
        self.layer?.cornerRadius = 2
        
        self.nameView.detailsCallback = { [weak self] in
            guard let s = self else { return }
            s.detailsState = !s.detailsState
            s.toggleDetails()
        }
        
        self.addArrangedSubview(self.nameView)
        self.addArrangedSubview(self.chartView)
        self.addArrangedSubview(self.barView)
        self.addArrangedSubview(self.legendView)
        self.addArrangedSubview(self.detailsView)
        
        self.toggleDetails()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.layer?.backgroundColor = (isDarkMode ? NSColor(red: 17/255, green: 17/255, blue: 17/255, alpha: 0.25) : NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1)).cgColor
    }
    
    public func update(free: Int64, smart: smart_t?) {
        self.nameView.update(free: free, read: nil, write: nil)
        self.legendView.update(free: free)
        self.barView.update(free: free)
        self.detailsView.update(smart: smart)
    }
    
    public func updateStats(stats: stats) {
        self.nameView.update(free: nil, read: stats.read, write: stats.write)
        self.chartView.update(read: stats.read, write: stats.write)
        self.detailsView.update(stats: stats)
    }
    public func setChartColor(read: NSColor? = nil, write: NSColor? = nil) {
        self.chartView.setColors(read: read, write: write)
    }
    public func setChartReverseOrder(_ newValue: Bool) {
        self.chartView.setReverseOrder(newValue)
    }
    
    private func toggleDetails() {
        if self.detailsState {
            self.addArrangedSubview(self.detailsView)
        } else {
            self.detailsView.removeFromSuperview()
        }
        
        let h = self.arrangedSubviews.map({ $0.bounds.height + self.spacing }).reduce(0, +) - 5 + 10
        self.setFrameSize(NSSize(width: self.frame.width, height: h))
        self.sizeCallback()
    }
}

internal class NameView: NSStackView {
    internal var detailsCallback: (() -> Void) = {}
    
    private let size: Int64
    private let uri: URL?
    private let finder: URL?
    private var ready: Bool = false
    
    private var readState: NSView? = nil
    private var writeState: NSView? = nil
    
    private var readColor: NSColor {
        SColor.fromString(Store.shared.string(key: "\(ModuleType.disk.stringValue)_readColor", defaultValue: SColor.secondBlue.key)).additional as! NSColor
    }
    private var writeColor: NSColor {
        SColor.fromString(Store.shared.string(key: "\(ModuleType.disk.stringValue)_writeColor", defaultValue: SColor.secondRed.key)).additional as! NSColor
    }
    
    public init(width: CGFloat, name: String, size: Int64, free: Int64, path: URL?) {
        self.size = size
        self.uri = path
        self.finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Finder")
        
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 16))
        
        self.orientation = .horizontal
        self.alignment = .centerY
        self.spacing = 4
        
        self.toolTip = localizedString("Open disk")
        
        let nameField = NSButton()
        nameField.bezelStyle = .inline
        nameField.isBordered = false
        nameField.contentTintColor = .labelColor
        nameField.action = #selector(self.openDisk)
        nameField.target = self
        nameField.toolTip = localizedString("Control")
        nameField.title = name
        nameField.cell?.truncatesLastVisibleLine = true
        
        let activity: NSStackView = NSStackView()
        activity.distribution = .fill
        activity.spacing = 2
        
        let readState: NSView = NSView()
        readState.widthAnchor.constraint(equalToConstant: 8).isActive = true
        readState.heightAnchor.constraint(equalToConstant: 8).isActive = true
        readState.wantsLayer = true
        readState.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.75).cgColor
        readState.layer?.cornerRadius = 4
        readState.toolTip = localizedString("Read")
        let writeState: NSView = NSView()
        writeState.widthAnchor.constraint(equalToConstant: 8).isActive = true
        writeState.heightAnchor.constraint(equalToConstant: 8).isActive = true
        writeState.wantsLayer = true
        writeState.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.75).cgColor
        writeState.layer?.cornerRadius = 4
        writeState.toolTip = localizedString("Write")
        self.readState = readState
        self.writeState = writeState
        
        activity.addArrangedSubview(readState)
        activity.addArrangedSubview(writeState)
        
        let button = NSButton()
        button.frame = CGRect(x: (self.frame.width/3)-20, y: 10, width: 15, height: 15)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imageScaling = NSImageScaling.scaleAxesIndependently
        button.contentTintColor = .lightGray
        button.action = #selector(self.toggleDetails)
        button.target = self
        button.toolTip = localizedString("Control")
        button.image = Bundle(for: Module.self).image(forResource: "tune")!
        
        self.addArrangedSubview(nameField)
        self.addArrangedSubview(activity)
        self.addArrangedSubview(NSView())
        self.addArrangedSubview(button)
        
        self.widthAnchor.constraint(equalToConstant: self.frame.width).isActive = true
        self.heightAnchor.constraint(equalToConstant: self.frame.height).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(free: Int64?, read: Int64?, write: Int64?) {
        if (self.window?.isVisible ?? false) || !self.ready {
            if let read = read {
                self.readState?.toolTip = "Read: \(Units(bytes: read).getReadableSpeed())"
                self.readState?.layer?.backgroundColor = read != 0 ? self.readColor.cgColor : NSColor.lightGray.withAlphaComponent(0.75).cgColor
            }
            if let write = write {
                self.writeState?.toolTip = "Write: \(Units(bytes: write).getReadableSpeed())"
                self.writeState?.layer?.backgroundColor = write != 0 ? self.writeColor.cgColor : NSColor.lightGray.withAlphaComponent(0.75).cgColor
            }
            self.ready = true
        }
    }
    
    @objc private func openDisk() {
        if let uri = self.uri, let finder = self.finder {
            NSWorkspace.shared.open([uri], withApplicationAt: finder, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    
    @objc private func toggleDetails() {
        self.detailsCallback()
    }
}

internal class ChartView: NSStackView {
    private var chart: NetworkChartView? = nil
    private var ready: Bool = false
    
    private var readColor: NSColor {
        SColor.fromString(Store.shared.string(key: "\(ModuleType.disk.stringValue)_readColor", defaultValue: SColor.secondBlue.key)).additional as! NSColor
    }
    private var writeColor: NSColor {
        SColor.fromString(Store.shared.string(key: "\(ModuleType.disk.stringValue)_writeColor", defaultValue: SColor.secondRed.key)).additional as! NSColor
    }
    private var reverseOrder: Bool {
        Store.shared.bool(key: "\(ModuleType.disk.stringValue)_reverseOrder", defaultValue: false)
    }
    
    public init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 36))
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 3
        
        let chart = NetworkChartView(frame: NSRect(
            x: 0,
            y: 1,
            width: self.frame.width,
            height: self.frame.height - 2
        ), num: 120, reversedOrder: self.reverseOrder, outColor: self.writeColor, inColor: self.readColor)
        chart.setTooltipState(false)
        self.chart = chart
        
        self.addArrangedSubview(chart)
        
        self.widthAnchor.constraint(equalToConstant: self.frame.width).isActive = true
        self.heightAnchor.constraint(equalToConstant: self.frame.height).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.layer?.backgroundColor = self.isDarkMode ? NSColor.lightGray.withAlphaComponent(0.1).cgColor : NSColor.white.cgColor
    }
    
    public func update(read: Int64, write: Int64) {
        self.chart?.addValue(upload: Double(write), download: Double(read))
    }
    
    public func setColors(read: NSColor? = nil, write: NSColor? = nil) {
        self.chart?.setColors(in: read, out: write)
    }
    
    public func setReverseOrder(_ newValue: Bool) {
        self.chart?.setReverseOrder(newValue)
    }
}

internal class BarView: NSView {
    private let size: Int64
    private var usedBarSpace: NSView? = nil
    private var ready: Bool = false
    
    private var background: NSView? = nil
    
    public init(width: CGFloat, size: Int64, free: Int64) {
        self.size = size
        
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        
        let view: NSView = NSView(frame: NSRect(x: 1, y: 0, width: self.frame.width - 2, height: self.frame.height))
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.secondaryLabelColor.cgColor
        view.layer?.borderWidth = 0.25
        view.layer?.cornerRadius = 3
        self.background = view
        
        let percentage = CGFloat(size - free) / CGFloat(size)
        let width: CGFloat = (view.frame.width * (percentage < 0 ? 0 : percentage)) / 1
        self.usedBarSpace = NSView(frame: NSRect(x: 0, y: 0, width: width, height: view.frame.height))
        self.usedBarSpace?.wantsLayer = true
        self.usedBarSpace?.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        
        view.addSubview(self.usedBarSpace!)
        self.addSubview(view)
        
        self.widthAnchor.constraint(equalToConstant: self.frame.width).isActive = true
        self.heightAnchor.constraint(equalToConstant: self.frame.height).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.background?.layer?.backgroundColor = self.isDarkMode ? NSColor.lightGray.withAlphaComponent(0.1).cgColor : NSColor.white.cgColor
    }
    
    public func update(free: Int64?) {
        if (self.window?.isVisible ?? false) || !self.ready {
            if let free = free, self.usedBarSpace != nil {
                let percentage = CGFloat(self.size - free) / CGFloat(self.size)
                let width: CGFloat = ((self.frame.width - 2) * (percentage < 0 ? 0 : percentage)) / 1
                self.usedBarSpace?.setFrameSize(NSSize(width: width, height: self.usedBarSpace!.frame.height))
            }
            
            self.ready = true
        }
    }
}

internal class LegendView: NSView {
    private let size: Int64
    private var free: Int64
    private let id: String
    private var ready: Bool = false
    
    private var showUsedSpace: Bool {
        get { Store.shared.bool(key: "\(self.id)_usedSpace", defaultValue: false) }
        set { Store.shared.set(key: "\(self.id)_usedSpace", value: newValue) }
    }
    
    private var legendField: NSTextField? = nil
    private var percentageField: NSTextField? = nil
    
    public init(width: CGFloat, id: String, size: Int64, free: Int64) {
        self.id = id
        self.size = size
        self.free = free
        
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 16))
        self.toolTip = localizedString("Switch view")
        
        let height: CGFloat = 14
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height))
        
        let legendField = TextView(frame: NSRect(x: 0, y: (view.frame.height-height)/2, width: view.frame.width - 40, height: height))
        legendField.font = NSFont.systemFont(ofSize: 11, weight: .light)
        legendField.stringValue = self.legend(free: free)
        legendField.cell?.truncatesLastVisibleLine = true
        
        let percentageField = TextView(frame: NSRect(x: view.frame.width - 40, y: (view.frame.height-height)/2, width: 40, height: height))
        percentageField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        percentageField.alignment = .right
        percentageField.stringValue = self.percentage(free: free)
        
        view.addSubview(legendField)
        view.addSubview(percentageField)
        self.addSubview(view)
        
        self.legendField = legendField
        self.percentageField = percentageField
        
        let trackingArea = NSTrackingArea(
            rect: CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height),
            options: [NSTrackingArea.Options.activeAlways, NSTrackingArea.Options.mouseEnteredAndExited, NSTrackingArea.Options.activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
        
        self.widthAnchor.constraint(equalToConstant: self.frame.width).isActive = true
        self.heightAnchor.constraint(equalToConstant: self.frame.height).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(free: Int64) {
        self.free = free
        
        if (self.window?.isVisible ?? false) || !self.ready {
            if let view = self.legendField {
                view.stringValue = self.legend(free: free)
            }
            if let view = self.percentageField {
                view.stringValue = self.percentage(free: free)
            }
            
            self.ready = true
        }
    }
    
    private func legend(free: Int64) -> String {
        var value: String
        
        if self.showUsedSpace {
            var usedSpace = self.size - free
            if usedSpace < 0 {
                usedSpace = 0
            }
            value = localizedString("Used disk memory", DiskSize(usedSpace).getReadableMemory(), DiskSize(self.size).getReadableMemory())
        } else {
            value = localizedString("Free disk memory", DiskSize(free).getReadableMemory(), DiskSize(self.size).getReadableMemory())
        }
        
        return value
    }
    
    private func percentage(free: Int64) -> String {
        guard self.size != 0 else {
            return "0%"
        }
        var percentage: Int
        
        if self.showUsedSpace {
            percentage = Int((Double(self.size - free) / Double(self.size)) * 100)
        } else {
            percentage = Int((Double(free) / Double(self.size)) * 100)
        }
        
        return "\(percentage < 0 ? 0 : percentage)%"
    }
    
    override func mouseEntered(with: NSEvent) {
        NSCursor.pointingHand.set()
    }
    
    override func mouseExited(with: NSEvent) {
        NSCursor.arrow.set()
    }
    
    override func mouseDown(with: NSEvent) {
        self.showUsedSpace = !self.showUsedSpace
        
        if let view = self.legendField {
            view.stringValue = self.legend(free: self.free)
        }
        if let view = self.percentageField {
            view.stringValue = self.percentage(free: self.free)
        }
    }
}

internal class DetailsView: NSStackView {
    private var smartHeight: CGFloat {
        get { (22*6) + Constants.Popup.separatorHeight }
    }
    
    private var readSpeedValueField: ValueField?
    private var writeSpeedValueField: ValueField?
    
    private var totalReadValueField: ValueField?
    private var totalWrittenValueField: ValueField?
    
    private var smartTotalReadValueField: ValueField?
    private var smartTotalWrittenValueField: ValueField?
    private var temperatureValueField: ValueField?
    private var healthValueField: ValueField?
    private var powerCyclesValueField: ValueField?
    private var powerOnHoursValueField: ValueField?
    
    private var readColor: NSColor {
        SColor.fromString(Store.shared.string(key: "\(ModuleType.disk.stringValue)_readColor", defaultValue: SColor.secondBlue.key)).additional as! NSColor
    }
    private var writeColor: NSColor {
        SColor.fromString(Store.shared.string(key: "\(ModuleType.disk.stringValue)_writeColor", defaultValue: SColor.secondRed.key)).additional as! NSColor
    }
    
    public init(width: CGFloat, id: String, smart: smart_t? = nil) {
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fillProportionally
        self.spacing = 0
        
        self.addArrangedSubview(self.initSpeed())
        self.addArrangedSubview(self.initSmart())
        
        self.recalculateHeight()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func recalculateHeight() {
        var h: CGFloat = 0
        self.arrangedSubviews.forEach { v in
            if let v = v as? NSStackView {
                h += v.arrangedSubviews.map({ $0.bounds.height }).reduce(0, +)
            } else {
                h += v.bounds.height
            }
        }
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
        }
    }
    
    private func initSpeed() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 88))
        view.widthAnchor.constraint(equalToConstant: view.bounds.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height))
        container.orientation = .vertical
        container.spacing = 0
        
        (_, _, self.readSpeedValueField) = popupWithColorRow(container, color: self.readColor, title: "\(localizedString("Read")):", value: "0 KB/s")
        (_, _, self.writeSpeedValueField) = popupWithColorRow(container, color: self.writeColor, title: "\(localizedString("Write")):", value: "0 KB/s")
        self.totalReadValueField = popupRow(container, title: "\(localizedString("Total read")):", value: "0 KB").1
        self.totalWrittenValueField = popupRow(container, title: "\(localizedString("Total written")):", value: "0 KB").1
        
        self.readSpeedValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.writeSpeedValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.totalReadValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.totalWrittenValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        
        view.addSubview(container)
        
        return view
    }
    
    private func initSmart() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.smartHeight))
        view.widthAnchor.constraint(equalToConstant: view.bounds.width).isActive = true
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(localizedString("SMART"), origin: NSPoint(x: 0, y: self.smartHeight-Constants.Popup.separatorHeight), width: self.frame.width)
        let container: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0
        
        self.smartTotalReadValueField = popupRow(container, title: "\(localizedString("Total read")):", value: "0 KB").1
        self.smartTotalWrittenValueField = popupRow(container, title: "\(localizedString("Total written")):", value: "0 KB").1
        self.temperatureValueField = popupRow(container, title: "\(localizedString("Temperature")):", value: "\(temperature(0))").1
        self.healthValueField = popupRow(container, title: "\(localizedString("Health")):", value: "0%").1
        self.powerCyclesValueField = popupRow(container, title: "\(localizedString("Power cycles")):", value: "0").1
        self.powerOnHoursValueField = popupRow(container, title: "\(localizedString("Power on hours")):", value: "0").1
        
        self.smartTotalReadValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.smartTotalWrittenValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.temperatureValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.healthValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.powerCyclesValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        self.powerOnHoursValueField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        
        view.addSubview(separator)
        view.addSubview(container)
        
        return view
    }
    
    public func update(stats: stats) {
        guard self.window?.isVisible ?? false else { return }
        
        self.readSpeedValueField?.stringValue = Units(bytes: stats.read).getReadableSpeed()
        self.writeSpeedValueField?.stringValue = Units(bytes: stats.write).getReadableSpeed()
        
        self.totalReadValueField?.stringValue = Units(bytes: stats.readBytes).getReadableMemory()
        self.totalReadValueField?.toolTip = "\(stats.readBytes / (512 * 1000))"
        self.totalWrittenValueField?.stringValue = Units(bytes: stats.writeBytes).getReadableMemory()
        self.totalWrittenValueField?.toolTip = "\(stats.writeBytes / (512 * 1000))"
    }
    
    public func update(smart: smart_t?) {
        guard self.window?.isVisible ?? false, let smart else { return }
        
        self.smartTotalReadValueField?.toolTip = "\(smart.totalRead / (512 * 1000))"
        self.smartTotalWrittenValueField?.toolTip = "\(smart.totalWritten / (512 * 1000))"
        self.smartTotalReadValueField?.stringValue = Units(bytes: smart.totalRead).getReadableMemory()
        self.smartTotalWrittenValueField?.stringValue = Units(bytes: smart.totalWritten).getReadableMemory()
        
        self.temperatureValueField?.stringValue = "\(temperature(Double(smart.temperature)))"
        self.healthValueField?.stringValue = "\(smart.life)%"
        
        self.powerCyclesValueField?.stringValue = "\(smart.powerCycles)"
        self.powerOnHoursValueField?.stringValue = "\(smart.powerOnHours)"
    }
}
