import Foundation
import CoreAudio
import AudioToolbox
import Combine

public struct AudioDeviceInfo: Identifiable, Hashable, Equatable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String

    public init(id: AudioDeviceID, name: String, uid: String) {
        self.id = id
        self.name = name
        self.uid = uid
    }
}

public final class AudioEngine: ObservableObject {
    public static let shared = AudioEngine()

    @Published public private(set) var defaultDeviceID: AudioDeviceID = kAudioObjectUnknown
    @Published public private(set) var deviceName: String = "No Input Device"
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var currentVolume: Float = 1.0
    @Published public private(set) var availableInputDevices: [AudioDeviceInfo] = []

    private var lastNonZeroVolume: Float = 0.8
    private var isUpdatingInternally: Bool = false

    // CoreAudio listener block pointers
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceMuteListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceVolumeListenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        setupSystemListeners()
        refreshDevice()
        refreshInputDevices()
    }

    deinit {
        removeCurrentDeviceListeners()
        removeSystemListeners()
    }

    // MARK: - Setup & System Listeners

    private func setupSystemListeners() {
        // 1. Default device listener
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevice()
            }
        }
        self.defaultDeviceListenerBlock = defaultBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            DispatchQueue.main,
            defaultBlock
        )

        // 2. Hardware devices list listener (for plugged/unplugged mics)
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshInputDevices()
                self?.refreshDevice()
            }
        }
        self.devicesListListenerBlock = devicesBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            DispatchQueue.main,
            devicesBlock
        )
    }

    private func removeSystemListeners() {
        if let block = defaultDeviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            defaultDeviceListenerBlock = nil
        }

        if let block = devicesListListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            devicesListListenerBlock = nil
        }
    }

    private func removeCurrentDeviceListeners() {
        guard defaultDeviceID != kAudioObjectUnknown else { return }

        if let block = deviceMuteListenerBlock {
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(defaultDeviceID, &muteAddress, DispatchQueue.main, block)
            deviceMuteListenerBlock = nil
        }

        if let block = deviceVolumeListenerBlock {
            var volAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(defaultDeviceID, &volAddress, DispatchQueue.main, block)
            deviceVolumeListenerBlock = nil
        }
    }

    private func attachCurrentDeviceListeners() {
        guard defaultDeviceID != kAudioObjectUnknown else { return }

        // Mute listener
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(defaultDeviceID, &muteAddress) {
            let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self = self, !self.isUpdatingInternally else { return }
                    self.updateMuteAndVolumeState()
                }
            }
            self.deviceMuteListenerBlock = muteBlock
            AudioObjectAddPropertyListenerBlock(defaultDeviceID, &muteAddress, DispatchQueue.main, muteBlock)
        }

        // Volume listener
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(defaultDeviceID, &volAddress) {
            let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self = self, !self.isUpdatingInternally else { return }
                    self.updateMuteAndVolumeState()
                }
            }
            self.deviceVolumeListenerBlock = volBlock
            AudioObjectAddPropertyListenerBlock(defaultDeviceID, &volAddress, DispatchQueue.main, volBlock)
        }
    }

    // MARK: - Device Refresh & Selection

    public func refreshDevice() {
        removeCurrentDeviceListeners()

        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        if status == noErr && deviceID != kAudioObjectUnknown {
            self.defaultDeviceID = deviceID
            self.deviceName = fetchDeviceName(for: deviceID)
            attachCurrentDeviceListeners()
            updateMuteAndVolumeState()
        } else {
            self.defaultDeviceID = kAudioObjectUnknown
            self.deviceName = "No Input Device"
            self.isMuted = true
            self.currentVolume = 0.0
        }
    }

    public func refreshInputDevices() {
        var propertySize = UInt32(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        guard status == noErr else { return }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        guard status == noErr else { return }

        var result: [AudioDeviceInfo] = []

        for id in deviceIDs {
            // Check input streams
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamSize = UInt32(0)
            status = AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            guard status == noErr && streamSize > 0 else { continue }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }

            status = AudioObjectGetPropertyData(id, &streamAddress, 0, nil, &streamSize, bufferListPointer)
            guard status == noErr else { continue }

            let numberBuffers = bufferListPointer.pointee.mNumberBuffers
            let channels = bufferListPointer.pointee.mBuffers.mNumberChannels
            guard numberBuffers > 0 && channels > 0 else { continue }

            let name = fetchDeviceName(for: id)
            let uid = fetchDeviceUID(for: id)
            result.append(AudioDeviceInfo(id: id, name: name, uid: uid))
        }

        self.availableInputDevices = result
    }

    public func selectDevice(_ deviceID: AudioDeviceID) {
        var newID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &newID
        )

        if status == noErr {
            refreshDevice()
        }
    }

    private func fetchDeviceName(for deviceID: AudioDeviceID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)
        if status == noErr, let cfName = name?.takeRetainedValue() {
            return cfName as String
        }
        return "Microphone"
    }

    private func fetchDeviceUID(for deviceID: AudioDeviceID) -> String {
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid)
        if status == noErr, let cfUID = uid?.takeRetainedValue() {
            return cfUID as String
        }
        return "\(deviceID)"
    }

    // MARK: - State Check

    private func updateMuteAndVolumeState() {
        guard defaultDeviceID != kAudioObjectUnknown else {
            self.isMuted = true
            return
        }

        let hwMuted = getHardwareMute()
        let vol = getVolume()
        self.currentVolume = vol

        if vol > 0.01 {
            self.lastNonZeroVolume = vol
        }

        let effectiveMuted = (hwMuted == true) || (vol <= 0.001)
        if self.isMuted != effectiveMuted {
            self.isMuted = effectiveMuted
        }
    }

    private func getHardwareMute() -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(defaultDeviceID, &address) else { return nil }

        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &mute)
        if status == noErr {
            return mute == 1
        }
        return nil
    }

    private func getVolume() -> Float {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectHasProperty(defaultDeviceID, &address) {
            let status = AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &vol)
            if status == noErr {
                return Float(vol)
            }
        }

        address.mElement = 1
        if AudioObjectHasProperty(defaultDeviceID, &address) {
            let status = AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &vol)
            if status == noErr {
                return Float(vol)
            }
        }

        return 1.0
    }

    // MARK: - Mute Actions

    @discardableResult
    public func toggleMute() -> Bool {
        let targetState = !isMuted
        setMute(targetState)
        return targetState
    }

    public func setMute(_ muted: Bool) {
        guard defaultDeviceID != kAudioObjectUnknown else { return }

        isUpdatingInternally = true
        defer { isUpdatingInternally = false }

        if muted {
            let currentVol = getVolume()
            if currentVol > 0.01 {
                lastNonZeroVolume = currentVol
            }

            setHardwareMute(true)
            setVolume(0.0)

            self.isMuted = true
            self.currentVolume = 0.0
        } else {
            setHardwareMute(false)

            let restoreVol = max(lastNonZeroVolume, 0.5)
            setVolume(restoreVol)

            self.isMuted = false
            self.currentVolume = restoreVol
        }

        SoundCueManager.shared.playCue(forMuted: muted)
        notifySketchyBar()
    }

    private func notifySketchyBar() {
        DispatchQueue.global(qos: .utility).async {
            let paths = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
            for path in paths {
                if FileManager.default.isExecutableFile(atPath: path) {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: path)
                    task.arguments = ["--trigger", "mic_change"]
                    try? task.run()
                    break
                }
            }
        }
    }

    private func setHardwareMute(_ muted: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(defaultDeviceID, &address) else { return }

        var isSettable: DarwinBoolean = false
        AudioObjectIsPropertySettable(defaultDeviceID, &address, &isSettable)
        guard isSettable.boolValue else { return }

        var muteVal: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &muteVal)
    }

    public func setVolume(_ volume: Float) {
        let clamped = max(0.0, min(1.0, volume))
        var volVal = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var isSettable: DarwinBoolean = false
        if AudioObjectHasProperty(defaultDeviceID, &address) {
            AudioObjectIsPropertySettable(defaultDeviceID, &address, &isSettable)
            if isSettable.boolValue {
                AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &volVal)
            }
        }

        for channel: UInt32 in 1...2 {
            address.mElement = channel
            if AudioObjectHasProperty(defaultDeviceID, &address) {
                isSettable = false
                AudioObjectIsPropertySettable(defaultDeviceID, &address, &isSettable)
                if isSettable.boolValue {
                    AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &volVal)
                }
            }
        }
    }
}
