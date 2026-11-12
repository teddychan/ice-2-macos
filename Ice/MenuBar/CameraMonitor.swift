//
//  CameraMonitor.swift
//  Ice
//

import CoreMediaIO
import OSLog

/// Reports whether any camera is in use, so hiding can pause while it is.
///
/// While an assessment-mode assertion is active, macOS 27 removes Control Center's camera
/// indicator from the menu bar, and no allowed system item or bundle brings it back. The
/// indicator can't be watched for directly (it is gone from MenuBarAgent's tree while hidden),
/// so this watches its cause instead: CoreMediaIO's "running somewhere" flag on each video
/// device. Reading the flag needs no camera permission.
@MainActor
final class CameraMonitor {
    /// Whether any camera is running in any process, as of the last check.
    private(set) var isCameraInUse = false

    /// Called on the main thread when ``isCameraInUse`` changes.
    var onChange: () -> Void = {}

    private var watchedDevices: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var devicesListener: CMIOObjectPropertyListenerBlock?
    private let logger = Logger(category: "Camera")

    private static let systemObject = CMIOObjectID(kCMIOObjectSystemObject)

    func start() {
        guard devicesListener == nil else {
            return
        }
        let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
        var address = Self.address(kCMIOHardwarePropertyDevices)
        let status = CMIOObjectAddPropertyListenerBlock(Self.systemObject, &address, .main, listener)
        if status == kCMIOHardwareNoError {
            devicesListener = listener
        } else {
            logger.error("Could not watch the camera list: \(status)")
        }
        update()
    }

    /// Re-reads the devices and their state. Listeners call this; ``MenuBarController``'s
    /// periodic refresh calls it too, in case a notification was missed.
    func update() {
        let devices = Self.devices()
        for (device, listener) in watchedDevices where !devices.contains(device) {
            var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            watchedDevices[device] = nil
        }
        for device in devices where watchedDevices[device] == nil {
            let listener: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            }
            var address = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            if CMIOObjectAddPropertyListenerBlock(device, &address, .main, listener) == kCMIOHardwareNoError {
                watchedDevices[device] = listener
            }
        }
        let inUse = devices.contains(where: Self.isRunning)
        guard inUse != isCameraInUse else {
            return
        }
        isCameraInUse = inUse
        logger.notice("Camera in use: \(inUse, privacy: .public)")
        onChange()
    }

    private static func devices() -> [CMIOObjectID] {
        var address = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == kCMIOHardwareNoError,
            size > 0
        else {
            return []
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(systemObject, &address, 0, nil, size, &used, &devices) == kCMIOHardwareNoError else {
            return []
        }
        return Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == kCMIOHardwareNoError
            && running != 0
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }
}
