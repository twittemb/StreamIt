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
    var dataStack = Queue<NSData>(maxCapacity: 1)
    var queue: dispatch_queue_t
    let footersData = "\r\n".dataUsingEncoding(NSUTF8StringEncoding)
    var connected = true
    var id: Int
    var dataToSend: NSData? {
        didSet {
            self.dataStack.enqueue(self.dataToSend!)
        }
    }
    
    init (id: Int, client: GCDAsyncSocket, queue: dispatch_queue_t){
        self.id = id
        self.client = client
        self.queue = queue
    }
    
    func close (){
        self.connected = false
    }
    
    func startStreaming () {
        dispatch_async(self.queue, { [unowned self] in
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
                    
                    let headersData = headers.dataUsingEncoding(NSUTF8StringEncoding)
                    
                    self.client.writeData(headersData, withTimeout: -1, tag: 0)
                }else{
                    if (self.client.connectedPort.hashValue == 0){
                        // y a personne en face ... on arrête d'envoyer des données
                        self.close()
                        print("Dropping client ...")
                    }
                    
                    if let data = self.dataStack.dequeue() {
                        let frameHeader = "\r\n--0123456789876543210\r\nContent-Type: image/jpeg\r\nContent-Length: \(data.length)\r\n\r\n"
                        let headersData = frameHeader.dataUsingEncoding(NSUTF8StringEncoding)
                        self.client.writeData(headersData, withTimeout: -1, tag: 0)
                        self.client.writeData(data, withTimeout: -1, tag: 0)
                        self.client.writeData(self.footersData, withTimeout: -1, tag: self.id)
                    }
                }
            }
            })
    }
}
