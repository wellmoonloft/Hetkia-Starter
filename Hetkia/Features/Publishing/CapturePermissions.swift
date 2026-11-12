import AVFoundation
import CoreLocation
import Foundation

enum CapturePreferences {
  static let writeLocationToLibraryKey = "hetkia.capture.writeLocationToLibrary"

  static var writeLocationToSavedPhotos: Bool {
    UserDefaults.standard.object(forKey: writeLocationToLibraryKey) as? Bool ?? true
  }

  static func setWriteLocationToSavedPhotos(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: writeLocationToLibraryKey)
  }

  @MainActor
  static var shouldAttachLocationWhenSaving: Bool {
    writeLocationToSavedPhotos && CapturePermissionStatus.isLocationAuthorized
  }
}

enum CapturePermissionStatus {
  static var isCameraAuthorized: Bool {
    AVCaptureDevice.authorizationStatus(for: .video) == .authorized
  }

  static var isCameraDeniedOrRestricted: Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .denied, .restricted:
      return true
    default:
      return false
    }
  }

  @MainActor
  static var isLocationAuthorized: Bool {
    switch CaptureLocationProvider.shared.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      return true
    default:
      return false
    }
  }

  @MainActor
  static var isLocationDeniedOrRestricted: Bool {
    switch CaptureLocationProvider.shared.authorizationStatus {
    case .denied, .restricted:
      return true
    default:
      return false
    }
  }

  @MainActor
  static func requestCameraAccess() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .video) { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }

  @MainActor
  static func requestLocationAccess() async -> Bool {
    let manager = CaptureLocationProvider.shared
    let status = manager.authorizationStatus
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      return true
    case .notDetermined:
      return await manager.requestWhenInUseAuthorization()
    default:
      return false
    }
  }
}

@MainActor
final class CaptureLocationProvider: NSObject, CLLocationManagerDelegate {
  static let shared = CaptureLocationProvider()

  private let manager = CLLocationManager()
  private var authorizationContinuation: CheckedContinuation<Bool, Never>?

  var authorizationStatus: CLAuthorizationStatus {
    manager.authorizationStatus
  }

  override private init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
  }

  func requestWhenInUseAuthorization() async -> Bool {
    if authorizationStatus == .notDetermined {
      return await withCheckedContinuation { continuation in
        authorizationContinuation = continuation
        manager.requestWhenInUseAuthorization()
      }
    }
    return CapturePermissionStatus.isLocationAuthorized
  }

  func currentLocation() async -> CLLocation? {
    guard CapturePreferences.shouldAttachLocationWhenSaving else { return nil }
    guard CapturePermissionStatus.isLocationAuthorized else { return nil }
    manager.requestLocation()
    return await withCheckedContinuation { continuation in
      locationContinuation = continuation
    }
  }

  private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in
      guard let authorizationContinuation else { return }
      let granted = CapturePermissionStatus.isLocationAuthorized
      self.authorizationContinuation = nil
      authorizationContinuation.resume(returning: granted)
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    Task { @MainActor in
      guard let locationContinuation else { return }
      self.locationContinuation = nil
      locationContinuation.resume(returning: locations.last)
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      guard let locationContinuation else { return }
      self.locationContinuation = nil
      locationContinuation.resume(returning: nil)
    }
  }
}
