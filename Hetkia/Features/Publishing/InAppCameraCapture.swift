#if !os(macOS)
import AVFoundation
import CoreLocation
import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum EssayCameraSaveService {
  private static func localized(_ key: String) -> String {
    HetkiaSystemLanguage.localizedString(key, comment: "")
  }

  /// Merges GPS into container metadata when allowed, without recompressing pixels when possible.
  static func libraryReadyData(from original: Data, location: CLLocation?, attachGPS: Bool) -> Data {
    guard attachGPS, let location else { return original }
    guard let source = CGImageSourceCreateWithData(original as CFData, nil),
          let containerType = CGImageSourceGetType(source) else {
      return original
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, containerType, 1, nil) else {
      return original
    }
    var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    properties.merge(gpsMetadata(for: location), uniquingKeysWith: { _, new in new })
    CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return original }
    return data as Data
  }

  @MainActor
  static func saveCaptured(photoData: Data, location: CLLocation?) async throws -> JournalPhotoRecord {
    let attachGPS = CapturePreferences.shouldAttachLocationWhenSaving
    let data = libraryReadyData(from: photoData, location: location, attachGPS: attachGPS)
    var createdIdentifier: String?
    try await PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCreationRequest.forAsset()
      let options = PHAssetResourceCreationOptions()
      request.addResource(with: .photo, data: data, options: options)
      request.creationDate = .now
      if let location, CapturePreferences.shouldAttachLocationWhenSaving {
        request.location = location
      }
      createdIdentifier = request.placeholderForCreatedAsset?.localIdentifier
    }
    guard let createdIdentifier,
          let asset = PHAsset.fetchAssets(withLocalIdentifiers: [createdIdentifier], options: nil).firstObject else {
      throw PublishError.imageEncoding(localized("publish.error.image.encode"))
    }
    guard var record = OnThisDayLibrary.transientPhotoRecords(for: [asset]).first else {
      throw PublishError.imageEncoding(localized("publish.error.image.encode"))
    }
    if let thumbnailPath = try? await PhotoAssetResolver.persistThumbnail(
      for: asset,
      targetSize: CGSize(width: 900, height: 900)
    ) {
      record.thumbnailRelativePath = thumbnailPath
    }
    return record
  }

  private static func gpsMetadata(for location: CLLocation) -> [CFString: Any] {
    let coord = location.coordinate
    var gps: [CFString: Any] = [
      kCGImagePropertyGPSLatitude: abs(coord.latitude),
      kCGImagePropertyGPSLatitudeRef: coord.latitude >= 0 ? "N" : "S",
      kCGImagePropertyGPSLongitude: abs(coord.longitude),
      kCGImagePropertyGPSLongitudeRef: coord.longitude >= 0 ? "E" : "W",
    ]
    if location.altitude != 0 {
      gps[kCGImagePropertyGPSAltitude] = abs(location.altitude)
      gps[kCGImagePropertyGPSAltitudeRef] = location.altitude >= 0 ? 0 : 1
    }
    let timestamp = location.timestamp
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy:MM:dd"
    gps[kCGImagePropertyGPSDateStamp] = formatter.string(from: timestamp)
    formatter.dateFormat = "HH:mm:ss"
    gps[kCGImagePropertyGPSTimeStamp] = formatter.string(from: timestamp)
    if location.horizontalAccuracy >= 0 {
      gps[kCGImagePropertyGPSHPositioningError] = location.horizontalAccuracy
    }
    return [kCGImagePropertyGPSDictionary: gps]
  }
}

final class EssayInAppCameraViewController: UIViewController {
  var onCancel: () -> Void = {}
  var onCaptured: (JournalPhotoRecord) -> Void = { _ in }

  private let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private let sessionQueue = DispatchQueue(label: "com.hetkia.essay-camera.session")
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var isCapturing = false

  private lazy var cancelButton: UIButton = {
    var config = UIButton.Configuration.plain()
    config.title = HetkiaSystemLanguage.localizedString("common.cancel", comment: "")
    config.baseForegroundColor = .white
    let button = UIButton(configuration: config)
    button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    return button
  }()

  private lazy var shutterButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = .white
    button.layer.cornerRadius = 34
    button.layer.borderWidth = 4
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
    button.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 68),
      button.heightAnchor.constraint(equalToConstant: 68),
    ])
    return button
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureSession()
    layoutChrome()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sessionQueue.async { [weak self] in
      self?.session.startRunning()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [weak self] in
      self?.session.stopRunning()
    }
  }

  private func layoutChrome() {
    let toolbar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    toolbar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(toolbar)
    let stack = UIStackView(arrangedSubviews: [cancelButton, shutterButton])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.distribution = .equalSpacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    toolbar.contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: toolbar.contentView.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: toolbar.contentView.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: toolbar.contentView.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: toolbar.contentView.bottomAnchor, constant: -16),
    ])
  }

  private func configureSession() {
    session.beginConfiguration()
    session.sessionPreset = .photo
    guard
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      session.commitConfiguration()
      return
    }
    session.addInput(input)
    if session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
      photoOutput.maxPhotoQualityPrioritization = .quality
      if #available(iOS 16.0, *) {
        photoOutput.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.last
          ?? photoOutput.maxPhotoDimensions
      } else {
        photoOutput.isHighResolutionCaptureEnabled = true
      }
    }
    session.commitConfiguration()
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.insertSublayer(preview, at: 0)
    previewLayer = preview
  }

  private func preferredPhotoSettings() -> AVCapturePhotoSettings {
    let codecs = photoOutput.availablePhotoCodecTypes
    let settings: AVCapturePhotoSettings
    if codecs.contains(.hevc) {
      settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
    } else if codecs.contains(.jpeg) {
      settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
    } else {
      settings = AVCapturePhotoSettings()
    }
    settings.photoQualityPrioritization = .quality
    if #available(iOS 16.0, *) {
      // Uses device max dimensions; matches still photo quality tier from the active format.
    } else if photoOutput.isHighResolutionCaptureEnabled {
      settings.isHighResolutionPhotoEnabled = true
    }
    return settings
  }

  @objc private func cancelTapped() {
    onCancel()
  }

  @objc private func shutterTapped() {
    guard !isCapturing else { return }
    isCapturing = true
    shutterButton.isEnabled = false
    let settings = preferredPhotoSettings()
    sessionQueue.async { [weak self] in
      guard let self else { return }
      photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }
}

extension EssayInAppCameraViewController: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    Task { @MainActor in
      defer {
        isCapturing = false
        shutterButton.isEnabled = true
      }
      guard error == nil, let data = photo.fileDataRepresentation() else {
        onCancel()
        return
      }
      do {
        let location = await CaptureLocationProvider.shared.currentLocation()
        let record = try await EssayCameraSaveService.saveCaptured(photoData: data, location: location)
        onCaptured(record)
      } catch {
        onCancel()
      }
    }
  }
}

struct InAppCameraCaptureView: UIViewControllerRepresentable {
  let onCancel: () -> Void
  let onCaptured: (JournalPhotoRecord) -> Void

  func makeUIViewController(context: Context) -> EssayInAppCameraViewController {
    let controller = EssayInAppCameraViewController()
    controller.onCancel = onCancel
    controller.onCaptured = onCaptured
    return controller
  }

  func updateUIViewController(_ uiViewController: EssayInAppCameraViewController, context: Context) {}
}
#endif
