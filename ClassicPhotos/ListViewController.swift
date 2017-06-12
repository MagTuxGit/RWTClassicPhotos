//
//  ListViewController.swift
//  ClassicPhotos
//
//  Created by Richard Turton on 03/07/2014.
//  Copyright (c) 2014 raywenderlich. All rights reserved.
//

import UIKit
import CoreImage

let dataSourceURL = URL(string:"http://www.raywenderlich.com/downloads/ClassicPhotosDictionary.plist")!

class ListViewController: UITableViewController {
  
  var photos = [PhotoRecord]()
  let pendingOperations = PendingOperations()
  
  //MARK: - Loading
  override func viewDidLoad() {
    super.viewDidLoad()
    self.title = "Classic Photos"
    fetchPhotoDetails()
  }
  
  func fetchPhotoDetails() {
    let request = URLRequest(url:dataSourceURL)
    UIApplication.shared.isNetworkActivityIndicatorVisible = true
    
    NSURLConnection.sendAsynchronousRequest(request, queue: OperationQueue.main) {response,data,error in
      if data != nil {
        guard let datasourceDictionary = try? PropertyListSerialization.propertyList(from: data!, options: .mutableContainers, format: nil) as! NSDictionary else {
          return
        }
        
        for (key,value) in datasourceDictionary {
          let name = key as? String
          let url = URL(string:value as? String ?? "")
          if name != nil && url != nil {
            let photoRecord = PhotoRecord(name:name!, url:url!)
            self.photos.append(photoRecord)
          }
        }
        
        self.tableView.reloadData()
      }
      
      if error != nil {
        let alert = UIAlertView(title:"Oops!",message:error!.localizedDescription, delegate:nil, cancelButtonTitle:"OK")
        alert.show()
      }
      UIApplication.shared.isNetworkActivityIndicatorVisible = false
    }
  }
  
  //MARK: UITableViewdataSource
  
  override func tableView(_ tableView: UITableView?, numberOfRowsInSection section: Int) -> Int {
    return photos.count
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "CellIdentifier", for: indexPath) 
    
    // show activity indicator
    if cell.accessoryView == nil {
      let indicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
      cell.accessoryView = indicator
    }
    let indicator = cell.accessoryView as! UIActivityIndicatorView
    
    // get photo details and configure the cell
    let photoDetails = photos[indexPath.row]
    
    cell.textLabel?.text = photoDetails.name
    cell.imageView?.image = photoDetails.image
    
    // operate with photo
    switch (photoDetails.state){
    case .filtered:
      indicator.stopAnimating()
    case .failed:
      indicator.stopAnimating()
      cell.textLabel?.text = "Failed to load"
    case .new, .downloaded:
      indicator.startAnimating()
      if (!tableView.isDragging && !tableView.isDecelerating) {
        self.startOperationsForPhotoRecord(photoDetails: photoDetails, indexPath: indexPath)
      }
    }
    
    return cell
  }
  
  //MARK: - Operations
  func startOperationsForPhotoRecord(photoDetails: PhotoRecord, indexPath: IndexPath){
    switch (photoDetails.state) {
    case .new:
      startDownloadForRecord(photoDetails: photoDetails, indexPath: indexPath)
    case .downloaded:
      startFiltrationForRecord(photoDetails: photoDetails, indexPath: indexPath)
    default:
      NSLog("do nothing")
    }
  }
  
  func startDownloadForRecord(photoDetails: PhotoRecord, indexPath: IndexPath){
    // check if operation is not executed already
    if pendingOperations.downloadsInProgress[indexPath] != nil {
      return
    }
    
    // create the downloader and add a completion block to it
    let downloader = ImageDownloader(photoRecord: photoDetails)
    downloader.completionBlock = {
      if downloader.isCancelled {
        return
      }
      
      DispatchQueue.main.async {
        self.pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
        self.tableView.reloadRows(at: [indexPath], with: .fade)
      }
    }
    
    // add operation to queue
    pendingOperations.downloadsInProgress[indexPath] = downloader
    pendingOperations.downloadQueue.addOperation(downloader)
  }
  
  func startFiltrationForRecord(photoDetails: PhotoRecord, indexPath: IndexPath){
    // check if operation is not executed already
    if pendingOperations.filtrationsInProgress[indexPath] != nil {
      return
    }
    
    // create the filterer and add a completion block to it
    let filterer = ImageFiltration(photoRecord: photoDetails)
    filterer.completionBlock = {
      if filterer.isCancelled {
        return
      }
      
      DispatchQueue.main.async {
        self.pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
        self.tableView.reloadRows(at: [indexPath], with: .fade)
      }
    }
    
    // add operation to queue
    pendingOperations.filtrationsInProgress[indexPath] = filterer
    pendingOperations.filtrationQueue.addOperation(filterer)
  }
  
  //MARK: - UIScrollView
  
  override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    // suspend all operations as soon as the user starts scrolling
    suspendAllOperations()
  }
  
  override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if !decelerate {
      // the user stopped dragging the table view
      loadImagesForOnscreenCells()
      resumeAllOperations()
    }
  }
  
  override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    // the user stopped dragging the table view
    loadImagesForOnscreenCells()
    resumeAllOperations()
  }
  
  func suspendAllOperations() {
    pendingOperations.downloadQueue.isSuspended = true
    pendingOperations.filtrationQueue.isSuspended = true
  }
  
  func resumeAllOperations() {
    pendingOperations.downloadQueue.isSuspended = false
    pendingOperations.filtrationQueue.isSuspended = false
  }
  
  func loadImagesForOnscreenCells() {
    // index paths of all the currently visible rows
    guard let pathsArray = tableView.indexPathsForVisibleRows else {
      return
    }
    
    // a set of all pending operations
    var allPendingOperations = Set(pendingOperations.downloadsInProgress.keys)
    allPendingOperations.formUnion(pendingOperations.filtrationsInProgress.keys)
    
    // subtract visible rows operations from operations to be cancelled
    var toBeCancelled = allPendingOperations
    let visiblePaths = Set(pathsArray)
    toBeCancelled.subtract(visiblePaths)
    
    // subtract pending operations from operations to be started
    var toBeStarted = visiblePaths
    toBeStarted.subtract(allPendingOperations)
    
    // cancel operations
    for indexPath in toBeCancelled {
      if let pendingDownload = pendingOperations.downloadsInProgress[indexPath] {
        pendingDownload.cancel()
      }
      pendingOperations.downloadsInProgress.removeValue(forKey: indexPath)
      if let pendingFiltration = pendingOperations.filtrationsInProgress[indexPath] {
        pendingFiltration.cancel()
      }
      pendingOperations.filtrationsInProgress.removeValue(forKey: indexPath)
    }
    
    // start operations
    for indexPath in toBeStarted {
      let recordToProcess = self.photos[indexPath.row]
      startOperationsForPhotoRecord(photoDetails: recordToProcess, indexPath: indexPath)
    }
  }
}
