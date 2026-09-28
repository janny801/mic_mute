import Foundation
import CoreAudio
import AudioToolbox
import Combine

public final class AudioEngine: ObservableObject {
    public static let shared = AudioEngine()

    @Published public private(set) var defaultDeviceID: AudioDeviceID = kAudioObjectUnknown
    @Published public private(set) var deviceName: String = "No Input Device"
    @Published public private(set) var isMuted: Bool = false
    @Published public private(set) var currentVolume: Float = 1.0

    private var lastNonZeroVolume: Float = 0.8
    private var isUpdatingInternally: Bool = false

    // CoreAudio listener block pointers
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceMuteListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceVolumeListenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        setupDefaultDeviceListener()
        refreshDevice()
    }

    deinit {
        removeCurrentDeviceListeners()
        removeDefaultDeviceListener()
    }

    // MARK: - Setup & Listeners

    private func setupDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevice()
            }
        }
        self.defaultDeviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
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

    // MARK: - Device Refresh

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

        // The device is considered muted if hardware mute is on OR volume is 0
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

        // Try channel 1 if element 0 was not present
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
            // Read current volume before muting so we can restore it accurately
            let currentVol = getVolume()
            if currentVol > 0.01 {
                lastNonZeroVolume = currentVol
            }

            // Set hardware mute if available
            setHardwareMute(true)

            // Set volume to 0.0 (universal system-level mute)
            setVolume(0.0)

            self.isMuted = true
            self.currentVolume = 0.0
        } else {
            // Unmute hardware if available
            setHardwareMute(false)

            // Restore volume
            let restoreVol = max(lastNonZeroVolume, 0.5)
            setVolume(restoreVol)

            self.isMuted = false
            self.currentVolume = restoreVol
        }

        // Play audio cue
        SoundCueManager.shared.playCue(forMuted: muted)
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

        // Try Main element
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

        // Also apply to channel 1 & 2 in case device has split channels
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
