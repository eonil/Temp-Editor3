//
//  FileNavigator.swift
//  Editor3
//
//  Created by Hoon H. on 2016/01/01.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Foundation
import AppKit

final class FileNavigator: OwnerfileNavigator {
	weak var ownerWorkspace: OwnerWorkspace?
	private var issues = Issues()
//	private(set) var issues = [FileNavigatorIssue]() {
//		didSet {
//			Event.Notification(sender: self, event: .DidChangeIssues).broadcast()
//		}
//	}
        private(set) var tree: FileNode? {
                didSet {
                        guard tree !== oldValue else { return }
			selection.removeAll()
                        Event.Notification(sender: self, event: .DidChangeTree).broadcast()
                }
        }
	var selection: [FileNode] = [] {
		willSet {
			assert(newValue.map { $0.rootNode() === tree }.reduce(true) { $0 && $1 })
		}
                didSet {
                        func equalityOf(a: [FileNode], _ b: [FileNode]) -> Bool {
                                guard a.count == b.count else { return false }
                                for i in 0..<a.count {
                                        guard a[i] === b[i] else { return false }
                                }
				return true
                        }
                        guard equalityOf(selection, oldValue) == false else { return }
                        Event.Notification(sender: self, event: .DidChangeSelection).broadcast()
                }
	}
	/// Reloads workspace file list. Conceptually, this synchronises current state to workspce's location.
	/// Non-nil `ownerWorkspace` is required.
	/// This will post to `issues` on any error.
	/// `tree` remains `nil` if loading failed.
	func reloadFileList() { reloadFileListImpl() }
	func persistFileList() { persistFileListImpl() }
	func canCreateNewFile() -> Bool { return canCreateNewFileImpl() }
	func canCreateNewFolder() -> Bool { return canCreateNewFolderImpl() }
	func canDelete() -> Bool { return canDeleteImpl() }
	func canShowInFinder() -> Bool { return canShowInFinderImpl() }
	func canShowInTerminal() -> Bool { return canShowInTerminalImpl() }
	func createNewFile() { return createNewFileImpl() }
	func createNewFolder() throws { return try createNewFolderImpl() }
	func dropFilesAtURLs(urls: [NSURL], ontoNode: FileNode) throws { return try dropFilesAtURLsImpl(urls, ontoNode: ontoNode) }
	func delete() { return deleteImpl() }
	func showInFinder() { return showInFinderImpl() }
	func showInTerminal() { return showInTerminalImpl() }
}
extension FileNavigator {
	enum Event {
		typealias Notification = EventNotification<FileNavigator,Event>
		case DidChangeTree
		case DidChangeSelection
		case DidChangeIssues
	}
	struct Issues {
		var cannotReloadFileList: Bool	=	false
		var cannotPersistFileList: Bool	=	false
	}
}
private extension FileNavigator {
	/// Errors are private and hidden from users because these informations are 
	/// intended for debugging, and not to inform users.
	private enum Error: ErrorType {
		case MissingOwnerWorkspace
		case MissingOwnerWorkspaceLocationURL
		case MissingFileTree
		case SnapshotDecodingFailureFromUTF8
		case SnapshotEncodingFailureIntoUTF8
	}
	private func getWorkspaceFileListURL() throws -> NSURL {
		guard let ownerWorkspace = ownerWorkspace else { throw Error.MissingOwnerWorkspace }
		guard let locationURL = ownerWorkspace.locationURL else { throw Error.MissingOwnerWorkspaceLocationURL }
		let workspaceFileListURL = locationURL.URLByAppendingPathComponent("Workspace.Editor3FileList")
		return workspaceFileListURL
	}
	private func reloadFileListImpl() {
		assert(ownerWorkspace != nil)
		checkAndReportFailureToDevelopers(ownerWorkspace != nil)
		do {
			tree = nil
			try {
				let workspaceFileListURL = try getWorkspaceFileListURL()
				let data = try NSData(contentsOfURL: workspaceFileListURL, options: [])
				guard let snapshot = NSString(data: data, encoding: NSUTF8StringEncoding) else { throw Error.SnapshotDecodingFailureFromUTF8 }
				tree = try FileNode(ownerFileNavigator: self, snapshot: snapshot as String)
			}()
			issues.cannotReloadFileList = false
		}
		catch let error {
			reportToDevelopers(error)
			issues.cannotReloadFileList = true
		}
	}
	private func persistFileListImpl() {
		assert(ownerWorkspace != nil)
		assert(tree != nil)
		checkAndReportFailureToDevelopers(ownerWorkspace != nil)
		checkAndReportFailureToDevelopers(tree != nil)
		do {
			try {
				let workspaceFileListURL = try getWorkspaceFileListURL()
				guard let tree = tree else { throw Error.MissingFileTree }
				let snapshot = tree.snapshot()
				guard let data = snapshot.dataUsingEncoding(NSUTF8StringEncoding) else { throw Error.SnapshotEncodingFailureIntoUTF8 }
				try data.writeToURL(workspaceFileListURL, options: [])
			}()
			issues.cannotPersistFileList = false
		}
		catch let error {
			reportToDevelopers(error)
			issues.cannotPersistFileList = true
		}
	}
	private func getFirstSelectedGroupNode() -> FileNode? {
		for node in selection {
			if node.isGroup { return node }
		}
		return nil
	}
	private func canCreateNewFileImpl() -> Bool {
		guard let _ = tree else { return false }
		guard selection.count == 1 else { return false }
		guard let parent = selection.first else { return false }
		guard parent.isGroup == true else { return false }
		guard let node = getFirstSelectedGroupNode() else { return false }
		assert(node.rootNode() === tree)
		guard node.rootNode() === tree else { return false }
		return true
	}
	private func createNewFileImpl() {
		// Catch errors and convert into issues.
		// Do not throw errors out.
		assert(canCreateNewFile())
		guard let parentNode = getFirstSelectedGroupNode() else { return reportToDevelopers() }
		let newSubnode = FileNode(ownerFileNavigator: self, name: "file0.rs")
		parentNode.appendSubnode(newSubnode)
		persistFileList()
	}
	private func canCreateNewFolderImpl() -> Bool {
		return canCreateNewFile()
	}
	private func createNewFolderImpl() throws {
		guard let ownerWorkspace = ownerWorkspace else { return }
		// Catch errors and convert into issues.
		// Do not throw errors out.
		assert(canCreateNewFolder())
		guard let parentNode = getFirstSelectedGroupNode() else { return reportToDevelopers() }
		func getNewFolderName() throws -> String {
			guard let parentFolderURL = parentNode.resolvePath().absoluteFileURLForWorkspace(ownerWorkspace) else {
				let reason = "Cannot resolve URL of selected file item node in workspace."
				throw FileNavigatorError.CannotCreateNewFolder(reason: reason)
			}
			for i in 0..<FileNavigationNewNameTrialMaxCount {
				let newNameCandidate = "folder\(i)"
				let newFolderURL = parentFolderURL.URLByAppendingPathComponent(newNameCandidate)
				guard newFolderURL.isExistingAsAnyFile() == false else { continue }
				return newNameCandidate
			}
			let reason = "Too many folders with default new folder name such as `folder0`."
			throw FileNavigatorError.CannotCreateNewFolder(reason: reason)
		}
		let newSubnode = FileNode(ownerFileNavigator: self, name: try getNewFolderName(), isGroup: true)
		parentNode.appendSubnode(newSubnode)
		persistFileList()

		// It's an error once registered folder cannot actually be created by any reason.
		guard let newFolderURL = newSubnode.resolvePath().absoluteFileURLForWorkspace(ownerWorkspace) else {
			throw FileNavigatorError.CannotResolvePathOfNodeAtPath(newSubnode.resolvePath())
		}
		do {
			try NSFileManager.defaultManager().createDirectoryAtURL(newFolderURL, withIntermediateDirectories: false, attributes: nil)
		}
		catch let error as EditorCommonUIPresentableErrorType {
			throw FileNavigatorError.CannotCreateNewFolder(reason: error)
		}
	}
	private func dropFilesAtURLsImpl(urls: [NSURL], ontoNode: FileNode) throws {
		guard let ownerWorkspace = ownerWorkspace else { return }
		// Create file nodes.
		// Just add all files regardless of actual existence.
		var appendedNodes = [FileNode]()
		for u in urls {
			let isNewNodeGroup = ((try? u.getExistence()) == .Directory) // Assumes as data-file if unknown.
			guard let newNodeName = u.lastPathComponent else { continue }
			let newNode = FileNode(ownerFileNavigator: self, name: newNodeName, isGroup: isNewNodeGroup)
			getFirstSelectedGroupNode()?.appendSubnode(newNode)
			appendedNodes.append(newNode)
		}
		persistFileList()
		// Copy file contents.
		// Do the best. Skip any errors, and throw them at last.
		var errorsInFileOperations = [FileNavigatorError]()
		for i in 0..<urls.count {
			let oldURL = urls[i]
			guard let newURL = appendedNodes[i].resolvePath().absoluteFileURLForWorkspace(ownerWorkspace) else { continue }
			do {
				try NSFileManager.defaultManager().copyItemAtURL(oldURL, toURL: newURL)
			}
			catch let error as EditorCommonUIPresentableErrorType {
				errorsInFileOperations.append(FileNavigatorError.CannotCopyFile(from: oldURL, to: newURL, reason: error))
			}
		}
		if errorsInFileOperations.count > 0 {
			throw FileNavigatorMultipleErrors(errors: errorsInFileOperations)
		}
	}
	private func canDeleteImpl() -> Bool {
		guard selection.contains({ $0 === tree }) == false else { return false }
		return selection.count > 0
	}
	private func deleteImpl() {
		assert(canDelete())
		// Deletes top containers only.
		for node in selection {
			guard node !== tree else { continue } 			//< Cannot remove root node.
			guard let supernode = node.supernode else { continue }
			guard node.rootNode() === tree else { continue }	//< Cannot remove detached node.
			supernode.removeSubnode(node)
		}
		persistFileList()
	}
	private func canShowInFinderImpl() -> Bool {
		return selection.count > 0
	}
	private func showInFinderImpl() {
		assert(canShowInFinder())
		assert(ownerWorkspace != nil)
		guard let ownerWorkspace = ownerWorkspace else { return }
		var urls = [NSURL]()
		for node in selection {
			guard let url = node.resolvePath().absoluteFileURLForWorkspace(ownerWorkspace) else { continue }
			urls.append(url)
		}
		NSWorkspace.sharedWorkspace().activateFileViewerSelectingURLs(urls)
	}
	private func canShowInTerminalImpl() -> Bool {
		return canShowInFinder()
	}
	private func showInTerminalImpl() {
		assert(canShowInTerminal())
		assert(ownerWorkspace != nil)
		guard let ownerWorkspace = ownerWorkspace else { return }
		for node in selection {
			guard let url = node.resolvePath().absoluteFileURLForWorkspace(ownerWorkspace) else { continue }
			system("open -a \"Terminal\" \"\(url)\"")
		}
	}
}

















































