//
//  CameraViewController.swift
//  StreamIt
//
//  Created by Thibault Wittemberg on 14/04/2016.
//  Copyright © 2016 Thibault Wittemberg. All rights reserved.
//

import UIKit
import AVFoundation
import CocoaAsyncSocket

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, GCDAsyncSocketDelegate {

    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var plusLabel: UILabel!
    @IBOutlet weak var minusLabel: UILabel!
    @IBOutlet weak var zoomSlider: UISlider!
    @IBOutlet weak var ledImage: UIImageView!
    @IBOutlet weak var informationButton: UIButton!
    @IBOutlet weak var addressLabel: UILabel!
    
    let ip = IPChecker.getIP()
    let captureSession = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer?
    var captureDevice: AVCaptureDevice?
    let videoOutput = AVCaptureVideoDataOutput()
    var clients = [Int:StreamingSession]()
    var serverSocket: GCDAsyncSocket?
    var clientSocket: GCDAsyncSocket?
    var previousOrientation = UIDeviceOrientation.Portrait
    
    let serverQueue = dispatch_queue_create("ServerQueue", DISPATCH_QUEUE_SERIAL)
    let clientQueue = dispatch_queue_create("ClientQueue", DISPATCH_QUEUE_CONCURRENT)
    let socketWriteQueue = dispatch_queue_create("SocketWriteQueue", DISPATCH_QUEUE_CONCURRENT)
    
    // Méthode du Delegate
    func socket(sock: GCDAsyncSocket!, didAcceptNewSocket newSocket: GCDAsyncSocket!) {
        print("Client has connected with IP \(newSocket.connectedHost)")
        let clientId = newSocket.connectedAddress.hashValue
        let newClient = StreamingSession(id: clientId, client: newSocket, queue: self.clientQueue)
        self.clients[clientId] = newClient
        newClient.startStreaming()
        
        dispatch_async(dispatch_get_main_queue(), {
            self.ledImage.image = UIImage(named: "led_red")
        })
    }
    
    func socket(sock: GCDAsyncSocket!, didConnectToHost host: String!, port: UInt16) {
        print ("Connected to \(host)")
        
        // enregistrement dans le broker MQTT
        let json = ["ip": "\(self.ip)",
                    "port": 10001,
                    "name": "\(UIDevice.currentDevice().name)",
                    "model": "\(UIDevice.currentDevice().model)",
                    "serial": "\(UIDevice.currentDevice().identifierForVendor!.description)",
                    "url": ["mjpeg":"/"],
                    "available": true,
                    "found": true
        ]
        
        if NSJSONSerialization.isValidJSONObject(json) { // True
            do {
                let rawData = try NSJSONSerialization.dataWithJSONObject(json, options: .PrettyPrinted)
                let readable = NSString(data: rawData, encoding: NSUTF8StringEncoding)
                let goodReadable = readable?.stringByReplacingOccurrencesOfString("\\/", withString: "/")
                sock.writeData(goodReadable!.dataUsingEncoding(NSUTF8StringEncoding), withTimeout: -1, tag: 0)
            } catch {
                print ("Failed contacting hmi.armonic ...")
            }
        }
        
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // on crée la socket de service
        // Le serveur tourne dans sa propre queue (les méthodes de délégate seront exécutées dans cette queue)
        // Les clients possèdent également leur propre queue dexécution
        print("Création du serveur sur l'IP \(self.ip)")
        self.serverSocket = GCDAsyncSocket(delegate: self, delegateQueue: self.serverQueue, socketQueue: self.socketWriteQueue)
        
        do {
            try self.serverSocket!.acceptOnInterface(self.ip, port: 10001)
        } catch {
            print("Could not listen on port 10001 ...")
        }
        
        // enregistrement dans le broker MQTT
        do {
            self.clientSocket = GCDAsyncSocket(delegate: self, delegateQueue: self.serverQueue)
            try self.clientSocket!.connectToHost("hmi.armonic", onPort: 43210, withTimeout: -1)
        } catch {
            print ("Failed contacting hmi.armonic ...")
        }
        
        // Do any additional setup after loading the view.
        self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720
        let devices = AVCaptureDevice.devices()
        
        for device in devices{
            if (device.hasMediaType(AVMediaTypeVideo)){
                self.captureDevice = device as? AVCaptureDevice
                if (captureDevice != nil) {
                    print("Capture Device Found")
                    beginSession()
                    break
                }
            }
        }
    }

    @IBAction func zoomChanged(sender: UISlider, forEvent event: UIEvent) {
        do {
            try self.captureDevice!.lockForConfiguration()
            self.captureDevice?.videoZoomFactor = CGFloat(sender.value)
            self.captureDevice!.unlockForConfiguration()
        }catch {
            
        }
    }
    
    @IBAction func informationPressed(sender: AnyObject) {
        self.addressLabel.text = "http://\(self.ip):10001"
        UIView.animateWithDuration(1, animations: {
            if (self.addressLabel.alpha == 0) {
                self.addressLabel.alpha = 1
            }
            else {
                self.addressLabel.alpha = 0
            }
        })
    }
    
    
    func beginSession () -> Void {
        do {
            try self.captureDevice!.lockForConfiguration()
            self.captureDevice!.focusMode = .ContinuousAutoFocus
            self.captureDevice!.unlockForConfiguration()
            if let maxZoom = self.captureDevice?.activeFormat.videoMaxZoomFactor {
                self.zoomSlider.maximumValue = Float(maxZoom)
            }
            
            try self.captureSession.addInput(AVCaptureDeviceInput(device: captureDevice))
            self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            
            let bounds = self.view.bounds
            
            self.previewLayer?.bounds = CGRect(origin: CGPointZero, size: CGSize(width: bounds.width, height: bounds.height))
            self.previewLayer?.videoGravity = AVLayerVideoGravityResize
            self.previewLayer?.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
            
            videoOutput.setSampleBufferDelegate(self, queue: dispatch_queue_create("AVSessionQueue", DISPATCH_QUEUE_SERIAL))
            self.captureSession.addOutput(videoOutput)
            self.cameraView.layer.addSublayer(self.previewLayer!)
            
            //self.previewLayer?.frame = self.view.layer.frame
            self.captureSession.startRunning()
            
        } catch {
            print ("Begin session failed")
        }
        
    }
    
    let context = CIContext(options:nil);
    
    func rotateLabels (angle: CGFloat) {
        dispatch_async(dispatch_get_main_queue(), {
            UIView.animateWithDuration(0.5, animations: {
                self.minusLabel.transform = CGAffineTransformRotate(CGAffineTransformIdentity, angle)
                self.plusLabel.transform = CGAffineTransformRotate(CGAffineTransformIdentity, angle)
                self.zoomSlider.transform = CGAffineTransformRotate(CGAffineTransformIdentity, CGFloat(0))
                self.informationButton.transform = CGAffineTransformRotate(CGAffineTransformIdentity, angle)
            })
        })
    }
    
    func switchLabels () {
        dispatch_async(dispatch_get_main_queue(), {
            UIView.animateWithDuration(0.5, animations: {
                let c1 = self.minusLabel.center
                let c2 = self.plusLabel.center
                
                let dx = c2.x - c1.x
                let dy = c2.y - c1.y
                
                
                self.minusLabel.transform = CGAffineTransformTranslate(CGAffineTransformIdentity, dx, dy)
                self.plusLabel.transform = CGAffineTransformTranslate(CGAffineTransformIdentity, -dx, -dy)
                
                self.minusLabel.transform = CGAffineTransformRotate(self.minusLabel.transform, CGFloat(-M_PI/2))
                self.plusLabel.transform = CGAffineTransformRotate(self.plusLabel.transform, CGFloat(-M_PI/2))
                
                
                self.zoomSlider.transform = CGAffineTransformRotate(CGAffineTransformIdentity, CGFloat(M_PI))
                
                self.informationButton.transform = CGAffineTransformRotate(CGAffineTransformIdentity, CGFloat(-M_PI/2))

            })
        })
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
        let currentOrientation = UIDevice.currentDevice().orientation
        if (currentOrientation != self.previousOrientation){
            
            switch (currentOrientation) {
            case .Portrait:
                self.videoOutput.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = AVCaptureVideoOrientation.Portrait
                self.rotateLabels(0)
                break
            case .LandscapeRight:
                self.videoOutput.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = AVCaptureVideoOrientation.LandscapeLeft
                self.switchLabels()
                break
            case .LandscapeLeft:
                self.videoOutput.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = AVCaptureVideoOrientation.LandscapeRight
                self.rotateLabels(CGFloat(M_PI/2))
                
                break
            case .PortraitUpsideDown:
                self.videoOutput.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
                self.rotateLabels(0)
                break
            default:
                self.videoOutput.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = AVCaptureVideoOrientation.Portrait
                self.rotateLabels(0)
                break
            }
            
            self.previousOrientation = currentOrientation
        }
        
        if (self.clients.count>0){
            
            let capture : CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            let sourceImage = CIImage(CVImageBuffer: capture, options: nil)
            let tempImage:CGImageRef = self.context.createCGImage(sourceImage, fromRect: sourceImage.extent)
            let image = UIImage(CGImage: tempImage);
            let imageToSend = UIImageJPEGRepresentation(image, 0);
            for (key, client) in self.clients {
                if (client.connected){
                    client.dataToSend = imageToSend?.copy() as! NSData
                }else{
                    self.clients.removeValueForKey(key)
                }
            }
            
            if (self.clients.count==0){
                dispatch_async(dispatch_get_main_queue(), {
                    self.ledImage.image = UIImage(named: "led_gray")
                })
            }
        }
        
    }


}
