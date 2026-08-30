import Flutter
import Foundation
import UIKit
import Photos
import TikTokOpenSDKCore
import TikTokOpenShareSDK

public class BombreelTiktokSharePlugin: NSObject, FlutterPlugin {

    private var pendingShareResult: FlutterResult?

    private let redirectURI =
        "https://bombreel-tiktok.web.app/tiktok/share/"

    public static func register(
        with registrar: FlutterPluginRegistrar
    ) {
        let channel = FlutterMethodChannel(
            name: "bombreel_tiktok_share",
            binaryMessenger: registrar.messenger()
        )

        let instance = BombreelTiktokSharePlugin()

        registrar.addMethodCallDelegate(
            instance,
            channel: channel
        )

        registrar.addApplicationDelegate(instance)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {

        case "getPlatformVersion":
            result(
                "iOS " + UIDevice.current.systemVersion
            )

        case "shareVideo":
            guard pendingShareResult == nil else {
                result(
                    FlutterError(
                        code: "SHARE_ALREADY_IN_PROGRESS",
                        message: "A TikTok share is already in progress.",
                        details: nil
                    )
                )
                return
            }

            guard
                let arguments =
                    call.arguments as? [String: Any],
                let videoPath =
                    arguments["videoPath"] as? String,
                !videoPath.isEmpty
            else {
                result(
                    FlutterError(
                        code: "INVALID_VIDEO_PATH",
                        message: "A valid video path or URL is required.",
                        details: nil
                    )
                )
                return
            }

            shareVideo(
                videoPath: videoPath,
                result: result
            )

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func shareVideo(
        videoPath: String,
        result: @escaping FlutterResult
    ) {
        requestPhotoLibraryAccess {
            [weak self] granted in

            guard let self = self else {
                DispatchQueue.main.async {
                    result(false)
                }
                return
            }

            guard granted else {
                DispatchQueue.main.async {
                    result(
                        FlutterError(
                            code: "PHOTO_PERMISSION_DENIED",
                            message: "Photo Library access is required to share the video to TikTok.",
                            details: nil
                        )
                    )
                }
                return
            }

            self.prepareLocalVideoURL(
                videoPath: videoPath
            ) {
                [weak self]
                localURL,
                shouldDeleteAfterUse,
                preparationError in

                guard let self = self else {
                    if
                        shouldDeleteAfterUse,
                        let localURL = localURL
                    {
                        try? FileManager.default
                            .removeItem(at: localURL)
                    }

                    DispatchQueue.main.async {
                        result(false)
                    }
                    return
                }

                if let preparationError =
                    preparationError
                {
                    DispatchQueue.main.async {
                        result(
                            FlutterError(
                                code: "VIDEO_PREPARATION_FAILED",
                                message: "BombReel could not prepare the video for TikTok.",
                                details:
                                    preparationError.localizedDescription
                            )
                        )
                    }
                    return
                }

                guard let localURL = localURL else {
                    DispatchQueue.main.async {
                        result(
                            FlutterError(
                                code: "VIDEO_NOT_FOUND",
                                message: "The BombReel video could not be prepared.",
                                details: videoPath
                            )
                        )
                    }
                    return
                }

                self.saveVideoToPhotos(
                    videoURL: localURL
                ) {
                    [weak self]
                    localIdentifier,
                    saveError in

                    if shouldDeleteAfterUse {
                        try? FileManager.default
                            .removeItem(at: localURL)
                    }

                    guard let self = self else {
                        DispatchQueue.main.async {
                            result(false)
                        }
                        return
                    }

                    if let saveError = saveError {
                        DispatchQueue.main.async {
                            result(
                                FlutterError(
                                    code: "PHOTO_SAVE_FAILED",
                                    message: "The video could not be saved to the Photo Library.",
                                    details:
                                        saveError.localizedDescription
                                )
                            )
                        }
                        return
                    }

                    guard
                        let localIdentifier =
                            localIdentifier
                    else {
                        DispatchQueue.main.async {
                            result(
                                FlutterError(
                                    code: "PHOTO_ASSET_MISSING",
                                    message: "The saved video did not return a Photo Library identifier.",
                                    details: nil
                                )
                            )
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        self.startTikTokShare(
                            localIdentifier:
                                localIdentifier,
                            result: result
                        )
                    }
                }
            }
        }
    }

    private func prepareLocalVideoURL(
        videoPath: String,
        completion:
            @escaping (
                URL?,
                Bool,
                Error?
            ) -> Void
    ) {
        if
            let remoteURL =
                URL(string: videoPath),
            let scheme =
                remoteURL.scheme?.lowercased(),
            scheme == "http" ||
                scheme == "https"
        {
            let task =
                URLSession.shared.downloadTask(
                    with: remoteURL
                ) {
                    temporaryURL,
                    response,
                    error in

                    if let error = error {
                        completion(
                            nil,
                            false,
                            error
                        )
                        return
                    }

                    guard
                        let httpResponse =
                            response
                                as? HTTPURLResponse,
                        (200...299).contains(
                            httpResponse.statusCode
                        )
                    else {
                        let statusCode =
                            (
                                response
                                    as? HTTPURLResponse
                            )?.statusCode ?? -1

                        completion(
                            nil,
                            false,
                            NSError(
                                domain:
                                    "BombreelTikTokShare",
                                code: 2001,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Video download failed with HTTP status \(statusCode)."
                                ]
                            )
                        )
                        return
                    }

                    guard
                        let temporaryURL =
                            temporaryURL
                    else {
                        completion(
                            nil,
                            false,
                            NSError(
                                domain:
                                    "BombreelTikTokShare",
                                code: 2002,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "The downloaded video file was not available."
                                ]
                            )
                        )
                        return
                    }

                    var fileExtension =
                        remoteURL.pathExtension

                    if fileExtension.isEmpty {
                        fileExtension = "mp4"
                    }

                    let destinationURL =
                        FileManager.default
                            .temporaryDirectory
                            .appendingPathComponent(
                                "bombreel_tiktok_\(UUID().uuidString)"
                            )
                            .appendingPathExtension(
                                fileExtension
                            )

                    do {
                        try FileManager.default
                            .moveItem(
                                at: temporaryURL,
                                to: destinationURL
                            )

                        completion(
                            destinationURL,
                            true,
                            nil
                        )

                    } catch {
                        completion(
                            nil,
                            false,
                            error
                        )
                    }
                }

            task.resume()
            return
        }

        let localURL: URL

        if
            videoPath.hasPrefix("file://"),
            let parsedURL =
                URL(string: videoPath)
        {
            localURL = parsedURL
        } else {
            localURL =
                URL(
                    fileURLWithPath:
                        videoPath
                )
        }

        guard
            FileManager.default.fileExists(
                atPath: localURL.path
            )
        else {
            completion(
                nil,
                false,
                NSError(
                    domain:
                        "BombreelTikTokShare",
                    code: 2003,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The local BombReel video file could not be found."
                    ]
                )
            )
            return
        }

        completion(
            localURL,
            false,
            nil
        )
    }

    private func requestPhotoLibraryAccess(
        completion: @escaping (Bool) -> Void
    ) {
        if #available(iOS 14, *) {

            let status =
                PHPhotoLibrary.authorizationStatus(
                    for: .readWrite
                )

            switch status {

            case .authorized, .limited:
                completion(true)

            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(
                    for: .readWrite
                ) { newStatus in
                    completion(
                        newStatus == .authorized ||
                        newStatus == .limited
                    )
                }

            default:
                completion(false)
            }

        } else {

            let status =
                PHPhotoLibrary.authorizationStatus()

            switch status {

            case .authorized:
                completion(true)

            case .notDetermined:
                PHPhotoLibrary.requestAuthorization {
                    newStatus in
                    completion(
                        newStatus == .authorized
                    )
                }

            default:
                completion(false)
            }
        }
    }

    private func saveVideoToPhotos(
        videoURL: URL,
        completion:
            @escaping (String?, Error?) -> Void
    ) {
        var localIdentifier: String?

        PHPhotoLibrary.shared().performChanges({

            let request =
                PHAssetChangeRequest
                    .creationRequestForAssetFromVideo(
                        atFileURL: videoURL
                    )

            localIdentifier =
                request?
                    .placeholderForCreatedAsset?
                    .localIdentifier

        }) { success, error in

            if
                success,
                let localIdentifier =
                    localIdentifier
            {
                completion(
                    localIdentifier,
                    nil
                )

                return
            }

            let finalError =
                error ??
                NSError(
                    domain:
                        "BombreelTikTokShare",
                    code: 1001,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Photos could not create a video asset."
                    ]
                )

            completion(
                nil,
                finalError
            )
        }
    }

    private func startTikTokShare(
        localIdentifier: String,
        result: @escaping FlutterResult
    ) {
        let request =
            TikTokShareRequest(
                localIdentifiers: [
                    localIdentifier
                ],
                mediaType: .video,
                redirectURI: redirectURI
            )

        pendingShareResult = result

        let launched = request.send(nil)

        if !launched {
            finishTikTokShare(
                succeeded: false
            )
        }
    }

    private func finishTikTokShare(
        succeeded: Bool
    ) {
        guard
            let result =
                pendingShareResult
        else {
            return
        }

        pendingShareResult = nil

        DispatchQueue.main.async {
            result(succeeded)
        }
    }

    private func isTikTokRedirectURL(
        _ url: URL
    ) -> Bool {
        guard
            let expectedURL =
                URL(string: redirectURI)
        else {
            return false
        }

        func normalizedPath(
            _ path: String
        ) -> String {
            if
                path.count > 1,
                path.hasSuffix("/")
            {
                return String(
                    path.dropLast()
                )
            }

            return path
        }

        return
            url.scheme?.lowercased() ==
                expectedURL.scheme?.lowercased() &&
            url.host?.lowercased() ==
                expectedURL.host?.lowercased() &&
            normalizedPath(url.path) ==
                normalizedPath(
                    expectedURL.path
                )
    }

    private func handleTikTokShareCallback(
        url: URL
    ) -> Bool {
        guard
            pendingShareResult != nil
        else {
            return false
        }

        guard
            isTikTokRedirectURL(url)
        else {
            return false
        }

        print(
            "BombReel TikTok callback URL: \(url.absoluteString)"
        )

        do {
            let response =
                try TikTokShareResponse(
                    fromURL: url,
                    redirectURI: redirectURI
                )

            let succeeded =
                response.errorCode == .noError

            print(
                "BombReel TikTok callback: errorCode=\(response.errorCode.rawValue), shareState=\(response.shareState.rawValue), success=\(succeeded)"
            )

            finishTikTokShare(
                succeeded: succeeded
            )

            return true

        } catch {
            print(
                "BombReel TikTok callback parse failed: \(error.localizedDescription)"
            )

            finishTikTokShare(
                succeeded: false
            )

            return true
        }
    }

    public func application(
        _ application: UIApplication,
        open url: URL,
        options:
            [UIApplication.OpenURLOptionsKey: Any]
            = [:]
    ) -> Bool {

        if handleTikTokShareCallback(
            url: url
        ) {
            return true
        }

        return TikTokURLHandler
            .handleOpenURL(url)
    }

    @objc(application:continueUserActivity:restorationHandler:)
    public func application(
        _ application: UIApplication,
        continue userActivity:
            NSUserActivity,
        restorationHandler:
            @escaping (
                [Any]?
            ) -> Void
    ) -> Bool {

        guard
            userActivity.activityType ==
                NSUserActivityTypeBrowsingWeb,
            let url =
                userActivity.webpageURL
        else {
            return false
        }

        if handleTikTokShareCallback(
            url: url
        ) {
            return true
        }

        return TikTokURLHandler
            .handleOpenURL(url)
    }
}
