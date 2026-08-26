import CoreFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AppRouteHandoffMonitor {
    private(set) var revision = 0

    init() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            appRouteHandoffArrivalCallback,
            AppRouteHandoffStore.arrivalNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(AppRouteHandoffStore.arrivalNotificationName as CFString),
            nil
        )
    }

    fileprivate func receiveArrival() {
        revision &+= 1
    }
}

private func appRouteHandoffArrivalCallback(
    _: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    _: CFNotificationName?,
    _: UnsafeRawPointer?,
    _: CFDictionary?
) {
    guard let observer else { return }
    let monitor = Unmanaged<AppRouteHandoffMonitor>
        .fromOpaque(observer)
        .takeUnretainedValue()
    Task { @MainActor in
        monitor.receiveArrival()
    }
}
