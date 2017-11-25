//
//  StreamingSession.swift
//  StreamIt
//
//  Created by Thibault Wittemberg on 14/04/2016.
//  Copyright © 2016 Thibault Wittemberg. All rights reserved.
//

import Foundation
import CocoaAsyncSocket



class StreamingSession {
    
    var client: GCDAsyncSocket
    var isHeadersSent = false
    var dataStack = Queue<Data>(maxCapacity: 1)
    var queue: DispatchQueue
    let footersData = "\r\n".data(using: String.Encoding.utf8)
    var connected = true
    var id: Int
    var dataToSend: Data? {
        didSet {
            self.dataStack.enqueue(self.dataToSend!)
        }
    }
    
    init (id: Int, client: GCDAsyncSocket, queue: DispatchQueue){
        self.id = id
        self.client = client
        self.queue = queue
    }
    
    func close (){
        self.connected = false
    }
    
    func startStreaming () {
        self.queue.async(execute: { [unowned self] in
            while (self.connected){
                
                if (!self.isHeadersSent) {
                    print("Sending headers ...")
                    self.isHeadersSent = true
                    let headers = "HTTP/1.0 200 OK\r\n" +
                        "Connection: keep-alive\r\n" +
                        "Ma-age: 0\r\n" +
                        "Expires: 0\r\n" +
                        "Cache-Control: no-store,must-revalidate\r\n" +
                        "Access-Control-Allow-Origin: *\r\n" +
                        "Access-Control-Allow-Headers: accept,content-type\r\n" +
                        "Access-Control-Allow-Methods: GET\r\n" +
                        "Access-Control-expose-headers: Cache-Control,Content-Encoding\r\n" +
                        "Pragma: no-cache\r\n" +
                    "Content-type: multipart/x-mixed-replace; boundary=0123456789876543210\r\n"
                    
                    let headersData = headers.data(using: String.Encoding.utf8)
                    
                    self.client.write(headersData!, withTimeout: -1, tag: 0)
                }else{
                    if (self.client.connectedPort.hashValue == 0){
                        // y a personne en face ... on arrête d'envoyer des données
                        self.close()
                        print("Dropping client ...")
                    }
                    
                    if let data = self.dataStack.dequeue() {
                        let frameHeader = "\r\n--0123456789876543210\r\nContent-Type: image/jpeg\r\nContent-Length: \(data.count)\r\n\r\n"
                        let headersData = frameHeader.data(using: String.Encoding.utf8)
                        self.client.write(headersData!, withTimeout: -1, tag: 0)
                        self.client.write(data, withTimeout: -1, tag: 0)
                        self.client.write(self.footersData!, withTimeout: -1, tag: self.id)
                    }
                }
            }
        })
    }
}
