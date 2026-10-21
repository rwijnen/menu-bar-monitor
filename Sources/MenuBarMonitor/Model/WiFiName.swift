import CoreLocation
import CoreWLAN
import Foundation

/// The name of the Wi-Fi network the Mac is on.
///
/// macOS treats a network's name as a clue to where you are, so it gives it only to
/// apps with Location Services permission. The app asks for that only when you click
/// the button in the network dropdown, never by itself, and never uses your location:
/// it does not start location updates at all. The name is shown and goes nowhere else.
@MainActor
final class WiFiName: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        /// Permission has not been asked for yet.
        case notAsked
        /// Permission was refused, or is turned off for every app.
        case denied
        /// Allowed, but not on Wi-Fi.
        case notOnWiFi
        case name(String)
    }

    /// Called when the permission changes, so the dropdown can update straight away.
    var onChange: (() -> Void)?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    var state: State {
        switch manager.authorizationStatus {
        case .notDetermined:
            return .notAsked
        case .denied, .restricted:
            return .denied
        default:
            guard let name = CWWiFiClient.shared().interface()?.ssid(), !name.isEmpty
            else { return .notOnWiFi }
            return .name(name)
        }
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onChange?() }
    }
}
