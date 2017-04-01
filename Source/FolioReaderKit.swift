//
//  FolioReaderKit.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Internal constants

internal let kApplicationDocumentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] 
internal let kCurrentFontFamily = "com.folioreader.kCurrentFontFamily"
internal let kCurrentFontSize = "com.folioreader.kCurrentFontSize"
internal let kCurrentAudioRate = "com.folioreader.kCurrentAudioRate"
internal let kCurrentHighlightStyle = "com.folioreader.kCurrentHighlightStyle"
internal let kCurrentMediaOverlayStyle = "com.folioreader.kMediaOverlayStyle"
internal let kCurrentScrollDirection = "com.folioreader.kCurrentScrollDirection"
internal let kNightMode = "com.folioreader.kNightMode"
internal let kCurrentTOCMenu = "com.folioreader.kCurrentTOCMenu"
internal let kHighlightRange = 30
internal let kReuseCellIdentifier = "com.folioreader.Cell.ReuseIdentifier"

/// Defines the media overlay and TTS selection
///
/// - `default`: The background is colored
/// - underline: The underlined is colored
/// - textColor: The text is colored
enum MediaOverlayStyle: Int {
    case `default`
    case underline
    case textColor
    
    init() {
        self = .default
    }
    
    func className() -> String {
        return "mediaOverlayStyle\(self.rawValue)"
    }
}

/// FolioReader actions delegate
@objc public protocol FolioReaderDelegate: class {

    /// Did finished loading book.
    ///
    /// - Parameters:
    ///   - folioReader: The FolioReader instance
    ///   - book: The Book instance
    @objc optional func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook)

    /// Called when reader did closed.
    ///
    /// - Parameter folioReader: The FolioReader instance
    @objc optional func folioReaderDidClose(_ folioReader: FolioReader)

	/// Called when reader did closed.
	@available(*, deprecated, message: "Use 'folioReaderDidClose(_ folioReader: FolioReader)' instead.")
	@objc optional func folioReaderDidClosed()
}

/// Main Library class with some useful constants and methods
open class FolioReader: NSObject {

	/// Internal init function to disable the creation of `FolioReader` objects outside the current scope.
	internal override init() { }

    /// Custom unzip path
    open var unzipPath				: String?
    
    /// FolioReaderDelegate
    open weak var delegate			: FolioReaderDelegate?

	// TODO_SMF_QUESTION: make those fileprivate (or internal) to avoid public access from other class?
    open weak var readerContainer	: FolioReaderContainer?
    open weak var readerAudioPlayer	: FolioReaderAudioPlayer?
	open weak var readerCenter		: FolioReaderCenter? {
		return self.readerContainer?.centerViewController
	}

    /// Check if reader is open
    var isReaderOpen = false
    
    /// Check if reader is open and ready
    var isReaderReady = false

    /// Check if layout needs to change to fit Right To Left
    var needsRTLChange: Bool {
        return (self.readerContainer?.book.spine.isRtl == true && self.readerContainer?.readerConfig.scrollDirection == .horizontal)
    }

	func isNight<T>(_ f: T, _ l: T) -> T {
		return (self.nightMode == true ? f : l)
	}

	/// UserDefault for the current ePub file.
	fileprivate var defaults: FolioReaderUserDefaults {

		guard
			let path = self.readerContainer?.epubPath,
			(path.isEmpty == false),
			let identifier = (path as? NSString)?.lastPathComponent,
			(identifier.isEmpty == false) else {
				fatalError("invalid user default unique identifier")
				return FolioReaderUserDefaults(withIdentifier: "")
		}

		return FolioReaderUserDefaults(withIdentifier: identifier)
	}
}

// MARK: - Present Folio Reader

extension FolioReader {

	/// Present a Folio Reader Container modally on a Parent View Controller.
	///
	/// - Parameters:
	///   - parentViewController: View Controller that will present the reader container.
	///   - epubPath: String representing the path on the disk of the ePub file. Must not be nil nor empty string.
	///   - config: FolioReader configuration.
	///   - shouldRemoveEpub: Boolean to remove the epub or not. Default true.
	///   - animated: Pass true to animate the presentation; otherwise, pass false.
	/// - Returns: The new and presented FolioReaderContainer instance.
	open class func presentReader(parentViewController: UIViewController, withEpubPath epubPath: String, andConfig config: FolioReaderConfig, shouldRemoveEpub: Bool = true, animated:
		Bool = true) -> FolioReaderContainer {
		let folioReader = FolioReader()
		let readerContainer = FolioReaderContainer(withConfig: config, folioReader: folioReader, epubPath: epubPath, removeEpub: shouldRemoveEpub)
		folioReader.readerContainer = readerContainer
		parentViewController.present(readerContainer, animated: animated, completion: nil)
		// Set the shared instance to support old version.
		FolioReader.shared = folioReader
		return readerContainer
	}
}

// MARK: -  Getters and setters for stored values

extension FolioReader {

	public func register(defaults: [String: Any]) {
		self.defaults.register(defaults: defaults)
	}

    /// Check if current theme is Night mode
    open var nightMode: Bool {
        get { return self.defaults.bool(forKey: kNightMode) }
        set (value) {
            self.defaults.set(value, forKey: kNightMode)

			if let readerCenter = self.readerCenter {
				UIView.animate(withDuration: 0.6, animations: {
					_ = readerCenter.currentPage?.webView.js("nightMode(\(self.nightMode))")
					readerCenter.pageIndicatorView?.reloadColors()
					readerCenter.configureNavBar()
					readerCenter.scrollScrubber?.reloadColors()
					readerCenter.collectionView.backgroundColor = (self.nightMode == true ? self.readerContainer?.readerConfig.nightModeBackground : UIColor.white)
					}, completion: { (finished: Bool) in
						NotificationCenter.default.post(name: Notification.Name(rawValue: "needRefreshPageMode"), object: nil)
				})
			}
        }
    }

    /// Check current font name. Default .andada
    open var currentFont: FolioReaderFont {
		get {
			guard
				let rawValue = self.defaults.value(forKey: kCurrentFontFamily) as? Int,
				let font = FolioReaderFont(rawValue: rawValue) else {
					return .andada
			}

			return font
		}
        set (font) {
            self.defaults.set(font.rawValue, forKey: kCurrentFontFamily)
			_ = self.readerCenter?.currentPage?.webView.js("setFontName('\(font.cssIdentifier)')")
        }
    }
    
    /// Check current font size. Default .m
    open var currentFontSize: FolioReaderFontSize {
		get {
			guard
				let rawValue = self.defaults.value(forKey: kCurrentFontSize) as? Int,
				let size = FolioReaderFontSize(rawValue: rawValue) else {
					return .m
			}

			return size
		}
        set (value) {
            self.defaults.set(value.rawValue, forKey: kCurrentFontSize)

			guard let currentPage = self.readerCenter?.currentPage else {
				return
			}

			currentPage.webView.js("setFontSize('\(currentFontSize.cssIdentifier)')")
        }
    }

    /// Check current audio rate, the speed of speech voice. Default 0
    var currentAudioRate: Int {
        get { return self.defaults.integer(forKey: kCurrentAudioRate) }
        set (value) {
            self.defaults.set(value, forKey: kCurrentAudioRate)
        }
    }

    /// Check the current highlight style.Default 0
    var currentHighlightStyle: Int {
        get { return self.defaults.integer(forKey: kCurrentHighlightStyle) }
        set (value) {
            self.defaults.set(value, forKey: kCurrentHighlightStyle)
        }
    }
    
    /// Check the current Media Overlay or TTS style
    var currentMediaOverlayStyle: MediaOverlayStyle {
        get {
			guard
				let rawValue = self.defaults.value(forKey: kCurrentMediaOverlayStyle) as? Int,
				let style = MediaOverlayStyle(rawValue: rawValue) else {
					return MediaOverlayStyle.default
			}

			return style
		}
        set (value) {
            self.defaults.set(value.rawValue, forKey: kCurrentMediaOverlayStyle)
        }
    }
    
    /// Check the current scroll direction. Default .defaultVertical
    open var currentScrollDirection: Int {
        get {
			// TODO_SMF_CHECK: when does this happen?
			guard let value = self.defaults.integer(forKey: kCurrentScrollDirection) as? Int else {
				return FolioReaderScrollDirection.defaultVertical.rawValue
			}

			return value
		}
        set (value) {
            self.defaults.set(value, forKey: kCurrentScrollDirection)

			let direction = (FolioReaderScrollDirection(rawValue: currentScrollDirection) ?? .defaultVertical)
			self.readerCenter?.setScrollDirection(direction)
        }
    }

	open var currentMenuIndex: Int {
		get { return self.defaults.integer(forKey: kCurrentTOCMenu) }
		set (value) {
			self.defaults.set(value, forKey: kCurrentTOCMenu)
		}
	}

	open var savedPositionForCurrentBook: [String: Any]? {
		get {
			guard let bookId = self.readerContainer?.book.name else {
				return nil
			}

			return self.defaults.value(forKey: bookId) as? [String : Any]
		}
		set {
			guard let bookId = self.readerContainer?.book.name else {
				return
			}

			self.defaults.set(newValue, forKey: bookId)
		}
	}
}

// MARK: - Image Cover

extension FolioReader {

	// TODO_SMF_QUESTION: the `getCoverImage` function used the shared instance before and ignored the parameter.
	// Should we properly implement the parameter or change the API to use the current FolioReader?

	/**
	Read Cover Image and Return an `UIImage`
	*/
	open class func getCoverImage(_ epubPath: String, unzipPath: String? = nil) -> UIImage? {
		return FREpubParser().parseCoverImage(epubPath, unzipPath: unzipPath)
	}

	open class func getTitle(_ epubPath: String) -> String? {
		return FREpubParser().parseTitle(epubPath)
	}

	open class func getAuthorName(_ epubPath: String) -> String? {
		return FREpubParser().parseAuthorName(epubPath)
	}
}

// MARK: - Exit, save and close FolioReader

extension FolioReader {

    /// Save Reader state, book, page and scroll offset.
    open func saveReaderState() {
        guard (self.isReaderOpen == true) else {
			return
		}
        
        guard
			let bookId = self.readerContainer?.book.name,
			let currentPage = self.readerCenter?.currentPage else {
				return
		}

		let position = [
			"pageNumber": (self.readerCenter?.currentPageNumber ?? 0),
			"pageOffsetX": currentPage.webView.scrollView.contentOffset.x,
			"pageOffsetY": currentPage.webView.scrollView.contentOffset.y
			] as [String : Any]

		self.savedPositionForCurrentBook = position
	}

    /// Closes and save the reader current instance.
    open func close() {
        self.saveReaderState()
        self.isReaderOpen = false
        self.isReaderReady = false
        self.readerAudioPlayer?.stop(immediate: true)
        self.defaults.set(0, forKey: kCurrentTOCMenu)
        self.delegate?.folioReaderDidClose?(self)
		self.delegate?.folioReaderDidClosed?()
    }
}

// MARK: - Public static functions. All Deprecated function

@available(*, deprecated, message: "Shared instance removed. Use a local instance instead.")
extension FolioReader {

	private static var _sharedInstance = FolioReader()
	open static var shared : FolioReader {
		get { return _sharedInstance }
		set { _sharedInstance = newValue }
	}

	/// Check the current Media Overlay or TTS style
	static var currentMediaOverlayStyle: MediaOverlayStyle {
		return FolioReader.shared.currentMediaOverlayStyle
	}

	/// Check if current theme is Night mode
	open class var nightMode: Bool {
		get { return FolioReader.shared.nightMode }
		set { FolioReader.shared.nightMode = newValue }
	}

	/// Check current font name
	open class var currentFont: FolioReaderFont {
		get { return FolioReader.shared.currentFont }
		set { FolioReader.shared.currentFont = newValue }
	}

	/// Check current font size
	open class var currentFontSize: FolioReaderFontSize {
		get { return FolioReader.shared.currentFontSize }
		set { FolioReader.shared.currentFontSize = newValue }
	}

	/// Check the current scroll direction
	open class var currentScrollDirection: Int {
		get { return FolioReader.shared.currentScrollDirection }
		set { FolioReader.shared.currentScrollDirection = newValue }
	}

	/// Check current audio rate, the speed of speech voice
	open class var currentAudioRate: Int {
		get { return FolioReader.shared.currentAudioRate }
		set { FolioReader.shared.currentAudioRate = newValue }
	}

	/// Check if reader is open and ready
	open class var isReaderReady : Bool {
		return FolioReader.shared.isReaderReady
	}

	/// Save Reader state, book, page and scroll are saved
	open class func saveReaderState() {
		FolioReader.shared.saveReaderState()
	}

	/// Closes and save the reader current instance
	open class func close() {
		FolioReader.shared.close()
	}

	/// Check the current highlight style
	open class var currentHighlightStyle: Int {
		get { return FolioReader.shared.currentHighlightStyle }
		set { FolioReader.shared.currentHighlightStyle = newValue }
	}

	/// Check if layout needs to change to fit Right To Left
	open class var needsRTLChange: Bool {
		return FolioReader.shared.needsRTLChange
	}
}

// MARK: - Application State

@available(*, deprecated, message: "Use 'saveReaderState()' on a FolioReaderContainer object instead.")
extension FolioReader {

	/// Called when the application will resign active
	open class func applicationWillResignActive() {
		FolioReader.shared.saveReaderState()
	}

	/// Called when the application will terminate
	open class func applicationWillTerminate() {
		FolioReader.shared.saveReaderState()
	}
}

// MARK: - Global Functions

@available(*, deprecated, message: "Shared instance removed. Use a local instance instead.")
func isNight<T> (_ f: T, _ l: T) -> T {
	return FolioReader.shared.isNight(f, l)
}

// MARK: - Scroll Direction Functions

@available(*, deprecated, message: "Shared instance removed. Use a local instance instead.")
func isDirection<T> (_ vertical: T, _ horizontal: T, _ horizontalContentVertical: T? = nil) -> T {
	return FolioReader.shared.readerContainer!.readerConfig.isDirection(vertical, horizontal, horizontalContentVertical)
}
