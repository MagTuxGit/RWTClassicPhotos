import UIKit

// This enum contains all the possible states a photo record can be in
enum PhotoRecordState {
    case new, downloaded, filtered, failed
}

class PhotoRecord {
    let name:String
    let url:URL
    var state = PhotoRecordState.new
    var image = UIImage(named: "Placeholder")
    
    init(name:String, url:URL) {
        self.name = name
        self.url = url
    }
}

class PendingOperations {
    lazy var downloadsInProgress = [IndexPath:Operation]()
    lazy var downloadQueue:OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Download queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    lazy var filtrationsInProgress = [IndexPath:Operation]()
    lazy var filtrationQueue:OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Image Filtration queue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
}

class ImageDownloader: Operation {
    let photoRecord: PhotoRecord
    
    init(photoRecord: PhotoRecord) {
        self.photoRecord = photoRecord
    }
    
    // perform work of Operation
    override func main() {
        // check for cancellation
        if self.isCancelled {
            return
        }
        
        // download image
        guard let imageData = try? Data(contentsOf:self.photoRecord.url) else {
            self.photoRecord.state = .failed
            self.photoRecord.image = UIImage(named: "Failed")
            return
        }

        // check for cancellation
        if self.isCancelled {
            return
        }
        
        // create image object
        self.photoRecord.image = UIImage(data:imageData)
        self.photoRecord.state = .downloaded
    }
}

class ImageFiltration: Operation {
    let photoRecord: PhotoRecord
    
    init(photoRecord: PhotoRecord) {
        self.photoRecord = photoRecord
    }
    
    func applySepiaFilter(image:UIImage) -> UIImage? {
        guard let imageData = UIImagePNGRepresentation(image) else {
            return image
        }
        let inputImage = CIImage(data: imageData)
        
        if self.isCancelled {
            return nil
        }
        
        let context = CIContext(options:nil)
        guard let filter = CIFilter(name:"CISepiaTone") else {
            return image
        }
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(0.8, forKey: "inputIntensity")
        guard let outputImage = filter.outputImage else {
            return image
        }
        
        if self.isCancelled {
            return nil
        }
        
        guard let outImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }
        return UIImage(cgImage: outImage)
    }
    
    override func main () {
        if self.isCancelled {
            return
        }
        
        if self.photoRecord.state != .downloaded {
            return
        }
        
        if let filteredImage = self.applySepiaFilter(image: self.photoRecord.image!) {
            self.photoRecord.image = filteredImage
            self.photoRecord.state = .filtered
        }
    }
}
