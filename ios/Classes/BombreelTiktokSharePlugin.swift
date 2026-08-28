import Flutter
import UIKit
import Photos
import TikTokOpenSDKCore
import TikTokOpenShareSDK

public class BombreelTiktokSharePlugin: NSObject, FlutterPlugin {

    private var shareRequest: TikTokShareRequest?

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
            guard shareRequest == nil else {
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
                let arguments = call.arguments as? [String: Any],
                let videoPath = arguments["videoPath"] as? String,
                !videoPath.isEmpty
            else {
                result(
                    FlutterError(
                        code: "INVALID_VIDEO_PATH",
                        message: "A valid video path is required.",
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
        let videoURL: URL

        if videoPath.hasPrefix("file://"),
           let parsedURL = URL(string: videoPath) {
            videoURL = parsedURL
        } else {
            videoURL = URL(fileURLWithPath: videoPath)
        }

        guard FileManager.default.fileExists(atPath: videoURL.path)
        else {
            result(
                FlutterError(
                    code: "VIDEO_NOT_FOUND",
                    message: "The BombReel video file could not be found.",
                    details: videoURL.path
                )
            )
            return
        }

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

            self.saveVideoToPhotos(
                videoURL: videoURL
            ) {
                [weak self] localIdentifier, error in

                guard let self = self else {
                    DispatchQueue.main.async {
                        result(false)
                    }
                    return
                }

                if let error = error {
                    DispatchQueue.main.async {
                        result(
                            FlutterError(
                                code: "PHOTO_SAVE_FAILED",
                                message: "The video could not be saved to the Photo Library.",
                                details: error.localizedDescription
                            )
                        )
                    }
                    return
                }

                guard let localIdentifier = localIdentifier
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
                        localIdentifier: localIdentifier,
                        result: result
                    )
                }
            }
        }
    }

    private func requestPhotoLibraryAccess(
        completion: @escaping (Bool) -> Void
    ) {
        if #available(iOS 14, *) {
            let status =
                PHPhotoLibrary.authorizationStatus(for: .readWrite)

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
            let status = PHPhotoLibrary.authorizationStatus()

            switch status {
            case .authorized:
                completion(true)

            case .notDetermined:
                PHPhotoLibrary.requestAuthorization {
                    newStatus in
                    completion(newStatus == .authorized)
                }

            default:
                completion(false)
            }
        }
    }

    private func saveVideoToPhotos(
        videoURL: URL,
        completion: @escaping (String?, Error?) -> Void
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

            if success,
               let localIdentifier = localIdentifier {
                completion(localIdentifier, nil)
                return
            }

            let finalError =
                error ??
                NSError(
                    domain: "BombreelTikTokShare",
                    code: 1001,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Photos could not create a video asset."
                    ]
                )

            completion(nil, finalError)
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

        shareRequest = request

        request.send {
            [weak self] response in

            guard let self = self else {
                DispatchQueue.main.async {
                    result(false)
                }
                return
            }

            defer {
                self.shareRequest = nil
            }

            guard
                let shareResponse =
                    response as? TikTokShareResponse
            else {
                print(
                    "BombReel TikTok share returned an unknown response."
                )

                DispatchQueue.main.async {
                    result(false)
                }
                return
            }

            if shareResponse.errorCode == .noError {
                print(
                    "BombReel TikTok share completed successfully."
                )

                DispatchQueue.main.async {
                    result(true)
                }

            } else {
                print(
                    "BombReel TikTok share failed. Error: \(shareResponse.errorCode.rawValue), share state: \(shareResponse.shareState)"
                )

                DispatchQueue.main.async {
                    result(false)
                }
            }
        }
    }

    public func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return TikTokURLHandler.handleOpenURL(url)
    }

    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler:
            @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard
            userActivity.activityType ==
                NSUserActivityTypeBrowsingWeb
        else {
            return false
        }

        return TikTokURLHandler.handleOpenURL(
            userActivity.webpageURL
        )
    }
}
