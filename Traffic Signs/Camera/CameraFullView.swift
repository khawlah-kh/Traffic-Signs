//
//  CameraFullView.swift
//  Hydro
//
//  Created by Khawlah Khalid on 16/07/2024.
//

import SwiftUI
import Foundation
import AVFoundation

struct CameraFullView: View {
    @EnvironmentObject var viewModel: ViewModel
//    @State private var capturedPhoto: UIImage?
//    @StateObject var trafficVM: TrafficSignDetector = .init(model: Traffic_Signs())

    @StateObject private var cameraController = CustomCameraController()
    var body: some View {
                ZStack{
                    CustomCameraView(cameraController: cameraController)
                        .ignoresSafeArea()
                    VStack{

                        Spacer()

                        if !cameraController.shouldCapture{
                            Text("No sign has been detected")
                                .foregroundStyle(Color.white)
                        }

                    }

                }
    }
    
    
}
#Preview {
    CameraFullView()
}

extension UIImage: Identifiable{
    
}
