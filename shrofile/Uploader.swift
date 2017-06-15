//
//  Uploader.swift
//  shrofile
//
//  Created by Jatin Garg on 14/06/17.
//  Copyright © 2017 Jatin Garg. All rights reserved.
//

import Foundation

class VideoUploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, ProgressReporting{
    var videouploadUrl: URL?
    var videoData: Data?
    var completionHandler: ((_ error: Error?, _ uploadURL: String?)->Void)?
    let fileName = "yo.mp4"
    let mimeType = "video/mp4"
    let fieldName = "file"
    var progress: Progress
    
    init(uploadUrl: URL, videoData: Data) {
        self.videouploadUrl = uploadUrl
        self.videoData = videoData
        progress = Progress(totalUnitCount: -1)
        progress.kind = ProgressKind.file
        progress.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
    }
    
    public func startUploading(){
        guard let url = self.videouploadUrl,let videoData = self.videoData else {return}
        
        var request = URLRequest(url: url)
        let boundaryConstant = "boundary-\(NSUUID().uuidString)"
        let contentType = "multipart/form-data; boundary=" + boundaryConstant
        request.httpMethod = "POST"
        request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        
        //setting data
        let body = NSMutableData()
        body.append("--\(boundaryConstant)\r\n".data(using: String.Encoding.utf8)!)
        body.append("Content-Disposition:form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: String.Encoding.utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: String.Encoding.utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: String.Encoding.utf8)!)
        body.append("--\(boundaryConstant)--\r\n".data(using: String.Encoding.utf8)!)
        
        request.httpBody = body as Data
        let configuraton = URLSessionConfiguration.default
        let session = URLSession(configuration: configuraton, delegate: self, delegateQueue: OperationQueue.main)
        

        let task = session.uploadTask(with: request, from: body as Data) { (data, response, error) in
            self.progress.completedUnitCount = self.progress.totalUnitCount
            if error != nil{
                print("Error while uploading: \(String(describing: error))")
                return
            }
            let parsedJson = (try! JSONSerialization.jsonObject(with: data!, options: [])) as! [String:Any]
            if let url = parsedJson["Url"] as? String{
                //upload was successful
                self.callCompletionHandler(withError: nil, uploadURL: url)
                
            }else{
                let error = NSError(domain: "Failed to upload", code: 303, userInfo: nil)
                self.callCompletionHandler(withError: error as Error , uploadURL: nil)
            }
            
        }
               print("Upload started")
        task.resume()
        
    }
    
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("upload complete")
        self.callCompletionHandler(withError: error, uploadURL: nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if progress.totalUnitCount == -1{
            progress.totalUnitCount = totalBytesExpectedToSend
        }
        progress.completedUnitCount = totalBytesSent
        let uploadProgress:Float = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        print("Upload progress: \(uploadProgress)")
    }
    
    private func callCompletionHandler(withError error: Error?, uploadURL url: String?){
        completionHandler?(error, url)
        completionHandler = nil
    }
   
}
