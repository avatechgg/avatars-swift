import SwiftUI
import WebKit
import SwiftUI
import WebKit
import Foundation
import Combine

public struct Message: Identifiable, Equatable {
    public let id = UUID()
    var text: String
    
    public init(_ text: String) {
        self.text = text
    }
}

@available(macOS 11.0, *)
public class AvatarViewModel: ObservableObject {
    @Published public var text: Message
    
    @Published public var avatarId: String
    @Published public var speakerId: String
    @Published public var x: Float
    @Published public var y: Float
    @Published public var scale: Float
    @Published public var rotation: Float
    
    public init(text: Message, avatarId: String, speakerId: String, x: Float = 0, y: Float = 0, scale: Float = 1, rotation: Float) {
        self.text = text
        self.avatarId = avatarId
        self.speakerId = speakerId
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
    }
}


@available(macOS 11.0, *)
public struct AvatarView: View {
    
    @StateObject var webViewStore = WebViewStore()
    
    @ObservedObject var viewModel: AvatarViewModel
    
    var isDevelopment = false
    
    public init(_ viewModel: AvatarViewModel, isDevelopment: Bool = false) {
        self.viewModel = viewModel
        self.isDevelopment = isDevelopment
    }
    
    func onCallback (eventName: String, value: String) {
        if (eventName == "clientReady") {
            sendEvent("avatarIdChange", viewModel.avatarId)
            sendEvent("speakerIdChange", viewModel.speakerId)
            sendEvent("xChange", String(viewModel.x))
            sendEvent("yChange", String(viewModel.y))
            sendEvent("scaleChange", String(viewModel.scale))
            sendEvent("rotationChange", String(viewModel.rotation))
        }
    }
    
    public var body: some View {
        WebView(webView: webViewStore.webView)
            .onReceive(viewModel.$text) { sendEvent("textChange", $0.text) }
            .onReceive(viewModel.$avatarId) { sendEvent("avatarIdChange", $0) }
            .onReceive(viewModel.$speakerId) { sendEvent("speakerIdChange", $0) }
            .onReceive(viewModel.$x) { sendEvent("xChange", String($0)) }
            .onReceive(viewModel.$y) { sendEvent("yChange", String($0)) }
            .onReceive(viewModel.$scale) { sendEvent("scaleChange", String($0)) }
            .onReceive(viewModel.$rotation) { sendEvent("rotationChange", String($0)) }
            .onAppear {
                self.webViewStore.messageHandler = MessageHandler(callbackAction: onCallback)
                
                if (self.isDevelopment) {
                    self.webViewStore.webView.load(URLRequest(url: URL(string: "http://localhost:3002/")!))
                } else {
                    self.webViewStore.webView.load(URLRequest(url: URL(string: "https://embed.api.avatech.ai/")!))
                }
            }
    }
    
    
    public func sendEvent(_ eventName: String,_ value: String) {
        self.webViewStore.webView.evaluateJavaScript(
            """
            window.sendHandleAvatarEvent('\(eventName)', '\(value)');
            """
        )
    }
}

public class MessageHandler: NSObject, WKScriptMessageHandler {
    
    var callbackAction: (String,String) -> ()
    
    public init (callbackAction: @escaping (String, String) -> ()) {
        self.callbackAction = callbackAction
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String : AnyObject] else {
            return
        }
        
        callbackAction(
            dict["eventName"] as! String,
            dict["value"] as! String
        )
    }
}


//https://github.com/kylehickinson/SwiftUI-WebView
@dynamicMemberLookup
public class WebViewStore: ObservableObject {
    
    @Published public var webView: WKWebView {
        didSet {
            setupObservers()
        }
    }
    
    @Published public var messageHandler: MessageHandler? {
        didSet {
            if (messageHandler != nil)
            {
                webView.configuration.userContentController.add(messageHandler!, name: "handleAvatarEvents")
            }
        }
    }
    
    public init() {
        let preferences = WKPreferences()
        //      preferences.javaScriptEnabled = true
        
        let configuration = WKWebViewConfiguration()
        //      configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes.video
#if os(iOS)
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        } else {
            configuration.requiresUserActionForMediaPlayback = false
        }
#endif
        configuration.preferences = preferences
        
        let webView = WKWebView(frame: CGRect.zero, configuration: configuration)
        
#if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
#endif
        
#if os(iOS)
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        
        if #available(iOS 14.0, *) {
            webView.backgroundColor = UIColor(.clear)
        } else {
            webView.backgroundColor = .clear
        }
#endif
        
        self.webView = webView
        setupObservers()
    }
    
    private func setupObservers() {
        func subscriber<Value>(for keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
            return webView.observe(keyPath, options: [.prior]) { _, change in
                if change.isPrior {
                    self.objectWillChange.send()
                }
            }
        }
        // Setup observers for all KVO compliant properties
        observers = [
            subscriber(for: \.title),
            subscriber(for: \.url),
            subscriber(for: \.isLoading),
            subscriber(for: \.estimatedProgress),
            subscriber(for: \.hasOnlySecureContent),
            subscriber(for: \.serverTrust),
            subscriber(for: \.canGoBack),
            subscriber(for: \.canGoForward)
        ]
        if #available(iOS 15.0, macOS 12.0, *) {
            observers += [
                subscriber(for: \.themeColor),
                subscriber(for: \.underPageBackgroundColor),
                subscriber(for: \.microphoneCaptureState),
                subscriber(for: \.cameraCaptureState)
            ]
        }
#if swift(>=5.7)
        if #available(iOS 16.0, macOS 13.0, *) {
            observers.append(subscriber(for: \.fullscreenState))
        }
#else
        if #available(iOS 15.0, macOS 12.0, *) {
            observers.append(subscriber(for: \.fullscreenState))
        }
#endif
    }
    
    private var observers: [NSKeyValueObservation] = []
    
    public subscript<T>(dynamicMember keyPath: KeyPath<WKWebView, T>) -> T {
        webView[keyPath: keyPath]
    }
}

#if os(iOS)
/// A container for using a WKWebView in SwiftUI
public struct WebView: View, UIViewRepresentable {
    /// The WKWebView to display
    public let webView: WKWebView
    
    public init(webView: WKWebView) {
        self.webView = webView
    }
    
    public func makeUIView(context: UIViewRepresentableContext<WebView>) -> WKWebView {
        webView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: UIViewRepresentableContext<WebView>) {
    }
}
#endif

#if os(macOS)
/// A container for using a WKWebView in SwiftUI
public struct WebView: View, NSViewRepresentable {
    /// The WKWebView to display
    public let webView: WKWebView
    
    public init(webView: WKWebView) {
        self.webView = webView
    }
    
    public func makeNSView(context: NSViewRepresentableContext<WebView>) -> WKWebView {
        webView
    }
    
    public func updateNSView(_ uiView: WKWebView, context: NSViewRepresentableContext<WebView>) {
    }
}
#endif
