import CryptoKit
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
enum PublishImageEncoder {
  static func jpegData(from photo: JournalPhotoRecord, savedOnly: Bool) async throws -> Data {
    let targetSize = CGSize(width: 2048, height: 2048)
    let image: CGImage?
    if savedOnly {
      image = await PhotoAssetResolver.thumbnailImage(relativePath: photo.thumbnailRelativePath, targetSize: targetSize)
    } else {
      image = await PhotoAssetResolver.displayImage(for: photo, targetSize: targetSize)
    }
    guard let image, let data = encodeJPEG(image) else {
      throw PublishError.imageEncoding(localized("publish.error.image.encode"))
    }
    return data
  }

  private static func encodeJPEG(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      data, UTType.jpeg.identifier as CFString, 1, nil
    ) else { return nil }
    let options: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: 0.85
    ]
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  private static func localized(_ key: String) -> String {
    HetkiaSystemLanguage.localizedString(key, comment: "")
  }
}

struct R2S3Client {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func validateAccess(config: PublishR2Configuration, accessKeyID: String, secretAccessKey: String) async throws {
    guard config.isFilled, !accessKeyID.isEmpty, !secretAccessKey.isEmpty else {
      throw PublishError.missingConfiguration(localized("publish.error.r2.missing"))
    }
    _ = try await signedRequest(
      method: "HEAD",
      bucket: config.bucketName,
      objectKey: "",
      config: config,
      accessKeyID: accessKeyID,
      secretAccessKey: secretAccessKey,
      body: nil
    )
  }

  func putJPEG(
    data: Data,
    objectKey: String,
    config: PublishR2Configuration,
    accessKeyID: String,
    secretAccessKey: String
  ) async throws {
    _ = try await signedRequest(
      method: "PUT",
      bucket: config.bucketName,
      objectKey: objectKey,
      config: config,
      accessKeyID: accessKeyID,
      secretAccessKey: secretAccessKey,
      body: data,
      contentType: "image/jpeg"
    )
  }

  func cdnURL(for objectKey: String, config: PublishR2Configuration) -> String? {
    guard let urlString = config.publicCDNURL(forStorageKey: objectKey),
          let url = URL(string: urlString) else { return nil }
    guard url.scheme == "https" || url.scheme == "http" else { return nil }
    return url.absoluteString
  }

  private func signedRequest(
    method: String,
    bucket: String,
    objectKey: String,
    config: PublishR2Configuration,
    accessKeyID: String,
    secretAccessKey: String,
    body: Data?,
    contentType: String? = nil
  ) async throws -> Data {
    guard let endpointHost = URL(string: config.endpoint)?.host else {
      throw PublishError.r2(localized("publish.error.r2.endpoint"))
    }
    let trimmedKey = objectKey.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let path = trimmedKey.isEmpty ? "/\(bucket)" : "/\(bucket)/\(trimmedKey)"
    guard let url = URL(string: "https://\(endpointHost)\(path)") else {
      throw PublishError.r2(localized("publish.error.r2.endpoint"))
    }

    let payload = body ?? Data()
    let payloadHash = SHA256.hash(data: payload).hexLowercased
    let amzDate = Self.amzDate()
    let dateStamp = String(amzDate.prefix(8))

    var headers: [String: String] = [
      "host": endpointHost,
      "x-amz-content-sha256": payloadHash,
      "x-amz-date": amzDate,
    ]
    if let contentType {
      headers["content-type"] = contentType
    }

    let canonicalHeaders = headers.sorted { $0.key < $1.key }
      .map { "\($0.key.lowercased()):\($0.value.trimmingCharacters(in: .whitespaces))" }
      .joined(separator: "\n") + "\n"
    let signedHeaderNames = headers.keys.map { $0.lowercased() }.sorted().joined(separator: ";")

    let canonicalRequest = [
      method,
      url.path,
      "",
      canonicalHeaders,
      signedHeaderNames,
      payloadHash,
    ].joined(separator: "\n")

    let credentialScope = "\(dateStamp)/auto/s3/aws4_request"
    let stringToSign = [
      "AWS4-HMAC-SHA256",
      amzDate,
      credentialScope,
      SHA256.hash(data: Data(canonicalRequest.utf8)).hexLowercased,
    ].joined(separator: "\n")

    let signature = Self.signature(
      secretKey: secretAccessKey,
      dateStamp: dateStamp,
      region: "auto",
      stringToSign: stringToSign
    )
    let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaderNames), Signature=\(signature)"

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    request.setValue(authorization, forHTTPHeaderField: "Authorization")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw PublishError.r2(localized("publish.error.r2.network"))
    }
    guard (200..<300).contains(http.statusCode) || (method == "HEAD" && http.statusCode == 404) else {
      let snippet = String(data: data, encoding: .utf8) ?? ""
      throw PublishError.r2("\(localized("publish.error.r2.failed")) (HTTP \(http.statusCode)) \(snippet)")
    }
    return data
  }

  private static func amzDate() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return formatter.string(from: Date())
  }

  private static func signature(secretKey: String, dateStamp: String, region: String, stringToSign: String) -> String {
    let kSecret = SymmetricKey(data: Data("AWS4\(secretKey)".utf8))
    let kDate = HMAC<SHA256>.authenticationCode(for: Data(dateStamp.utf8), using: kSecret)
    let kRegion = HMAC<SHA256>.authenticationCode(for: Data(region.utf8), using: SymmetricKey(data: Data(kDate)))
    let kService = HMAC<SHA256>.authenticationCode(for: Data("s3".utf8), using: SymmetricKey(data: Data(kRegion)))
    let kSigning = HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: SymmetricKey(data: Data(kService)))
    let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(kSigning)))
    return Data(signature).hexLowercased
  }

  private func localized(_ key: String) -> String {
    HetkiaSystemLanguage.localizedString(key, comment: "")
  }
}

private extension SHA256.Digest {
  var hexLowercased: String {
    map { String(format: "%02x", $0) }.joined()
  }
}

private extension Data {
  var hexLowercased: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
