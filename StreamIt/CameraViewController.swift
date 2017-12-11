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

class CameraViewController: UIViewController {

    @IBOutlet fileprivate weak var cameraView: UIView!
    @IBOutlet fileprivate weak var plusLabel: UILabel!
    @IBOutlet fileprivate weak var minusLabel: UILabel!
    @IBOutlet fileprivate weak var zoomSlider: UISlider!
    @IBOutlet fileprivate weak var ledImage: UIImageView!
    @IBOutlet fileprivate weak var informationLabel: UILabel!

    fileprivate let ip = IPChecker.getIP()
    fileprivate let captureSession = AVCaptureSession()
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer?
    fileprivate var captureDevice: AVCaptureDevice?
    fileprivate let videoOutput = AVCaptureVideoDataOutput()
    fileprivate var clients = [Int: StreamingSession]()
    fileprivate var serverSocket: GCDAsyncSocket?
    fileprivate var previousOrientation = UIDeviceOrientation.unknown
    fileprivate var ipIsDisplayed = false
    fileprivate var ipAddress = ""

    fileprivate let serverQueue = DispatchQueue(label: "ServerQueue", attributes: [])
    fileprivate let clientQueue = DispatchQueue(label: "ClientQueue", attributes: .concurrent)
    fileprivate let socketWriteQueue = DispatchQueue(label: "SocketWriteQueue", attributes: .concurrent)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // on crée la socket de service
        // Le serveur tourne dans sa propre queue (les méthodes de délégate seront exécutées dans cette queue)
        // Les clients possèdent également leur propre queue dexécution
        print("Création du serveur sur l'IP \(String(describing: self.ip))")
        self.serverSocket = GCDAsyncSocket(delegate: self, delegateQueue: self.serverQueue, socketQueue: self.socketWriteQueue)

        do {
            try self.serverSocket?.accept(onInterface: self.ip, port: 10001)
        } catch {
            print("Could not start listening on port 10001 (\(error))")
        }

        // Do any additional setup after loading the view.
        self.captureSession.sessionPreset = .medium
        let devices = AVCaptureDevice.devices()

        for device in devices {
            if device.hasMediaType(.video) {
                self.captureDevice = device
                if captureDevice != nil {
                    print("Capture device found")
                    beginSession()
                    break
                }
            }
        }

        if let ip = self.ip {
            ipAddress = "http://\(ip):10001"
        } else {
            ipAddress = "IP address not available"
        }

        self.cameraView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(CameraViewController.tapOnCameraView)))
    }

    // MARK: - Actions

    @objc fileprivate func tapOnCameraView() {

        UIView.animate(withDuration: 1, animations: { [unowned self] in
            if self.ipIsDisplayed {
                self.informationLabel.alpha = 0
            } else {
                self.informationLabel.alpha = 1
                self.informationLabel.text = self.ipAddress
            }

            self.ipIsDisplayed = !self.ipIsDisplayed
        })
    }

    @IBAction fileprivate func zoomChanged(_ sender: UISlider, forEvent event: UIEvent) {
        do {
            try self.captureDevice?.lockForConfiguration()
            self.captureDevice?.videoZoomFactor = CGFloat(sender.value)
            self.captureDevice?.unlockForConfiguration()
        } catch {
            print("Could not lock configuration for capture device (\(error))")
        }
    }

    // MARK: - Helpers

    fileprivate func beginSession() {
        do {
            guard let captureDevice = self.captureDevice else {
                print("Could not find a capture device")
                return
            }

            try captureDevice.lockForConfiguration()
            captureDevice.focusMode = .continuousAutoFocus
            captureDevice.unlockForConfiguration()

            let maxZoom = captureDevice.activeFormat.videoMaxZoomFactor
            self.zoomSlider.maximumValue = Float(maxZoom) / 2

            try self.captureSession.addInput(AVCaptureDeviceInput(device: captureDevice))
            self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            guard let previewLayer = self.previewLayer else {
                print("Could not create a preview layer for session")
                return
            }

            let bounds = self.view.bounds

            previewLayer.bounds = CGRect(origin: CGPoint.zero, size: CGSize(width: bounds.width, height: bounds.height))
            previewLayer.videoGravity = .resize
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "AVSessionQueue", attributes: []))
            self.captureSession.addOutput(videoOutput)
            self.cameraView.layer.addSublayer(previewLayer)

            //self.previewLayer?.frame = self.view.layer.frame
            self.captureSession.startRunning()
        } catch {
            print("Could not begin a capture session (\(error))")
        }
    }

    let context = CIContext(options: nil)

    fileprivate func rotateLabels(_ angle: CGFloat) {
        DispatchQueue.main.async(execute: {
            UIView.animate(withDuration: 0.5, animations: {
                self.minusLabel.transform = CGAffineTransform.identity.rotated(by: angle)
                self.plusLabel.transform = CGAffineTransform.identity.rotated(by: angle)
                self.zoomSlider.transform = CGAffineTransform.identity.rotated(by: CGFloat(0))
                self.informationLabel.transform = CGAffineTransform.identity.rotated(by: angle)
            })
        })
    }

    fileprivate func switchLabels() {
        DispatchQueue.main.async(execute: {
            UIView.animate(withDuration: 0.5, animations: {
                let c1 = self.minusLabel.center
                let c2 = self.plusLabel.center

                let dx = c2.x - c1.x
                let dy = c2.y - c1.y

                self.minusLabel.transform = CGAffineTransform.identity.translatedBy(x: dx, y: dy)
                self.plusLabel.transform = CGAffineTransform.identity.translatedBy(x: -dx, y: -dy)

                self.minusLabel.transform = self.minusLabel.transform.rotated(by: CGFloat(-1/2 * Double.pi))
                self.plusLabel.transform = self.plusLabel.transform.rotated(by: CGFloat(-1/2 * Double.pi))

                self.zoomSlider.transform = CGAffineTransform.identity.rotated(by: CGFloat(Double.pi))

                self.informationLabel.transform = CGAffineTransform.identity.rotated(by: CGFloat(-1/2 * Double.pi))

            })
        })
    }

    fileprivate func updateOrientation() {
        let currentOrientation = UIDevice.current.orientation
        if currentOrientation != self.previousOrientation {
            switch currentOrientation {
            case .portrait:
                self.videoOutput.connection(with: .video)?.videoOrientation = .portrait
                self.rotateLabels(0)
            case .landscapeRight:
                self.videoOutput.connection(with: .video)?.videoOrientation = .landscapeLeft
                self.switchLabels()
            case .landscapeLeft:
                self.videoOutput.connection(with: .video)?.videoOrientation = .landscapeRight
                self.rotateLabels(CGFloat(1/2 * Double.pi))
            case .portraitUpsideDown:
                self.videoOutput.connection(with: .video)?.videoOrientation = .portraitUpsideDown
                self.rotateLabels(0)
            default:
                self.videoOutput.connection(with: .video)?.videoOrientation = .portrait
                self.rotateLabels(0)
            }

            self.previousOrientation = currentOrientation
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        self.updateOrientation()

        if !self.clients.isEmpty {
            guard let capture: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let sourceImage = CIImage(cvImageBuffer: capture, options: nil)
            guard let tempImage = self.context.createCGImage(sourceImage, from: sourceImage.extent) else { return }
            let image = UIImage(cgImage: tempImage)
            let imageToSend = UIImageJPEGRepresentation(image, 0)

            for (key, client) in self.clients {
                if client.connected {
                    client.dataToSend = (imageToSend as NSData?)?.copy() as? Data
                } else {
                    self.clients.removeValue(forKey: key)
                }
            }

            if self.clients.isEmpty {
                DispatchQueue.main.async(execute: {
                    self.ledImage.image = UIImage(named: "led_gray")
                })
            }
        }
    }
}

// MARK: - GCDAsyncSocketDelegate

extension CameraViewController: GCDAsyncSocketDelegate {

    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        print("New client from IP \(newSocket.connectedHost ?? "unknown")")
        guard let clientId = newSocket.connectedAddress?.hashValue else { return }

        let newClient = StreamingSession(id: clientId, client: newSocket, queue: self.clientQueue)
        self.clients[clientId] = newClient
        newClient.startStreaming()

        DispatchQueue.main.async(execute: {
            self.ledImage.image = UIImage(named: "led_red")
        })
    }
}
