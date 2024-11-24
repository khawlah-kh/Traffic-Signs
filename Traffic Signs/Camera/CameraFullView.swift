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
    @StateObject private var cameraController = CustomCameraController()
    var body: some View {
        ZStack{
            CustomCameraView(cameraController: cameraController)
                .ignoresSafeArea()
            VStack{
                
                Spacer()
                Spacer()
                Text(cameraController.className.isEmpty ? "No sign has been detected" : cameraController.className )
                    .foregroundStyle(Color.white)
                Spacer()
                
            }
            
        }
    }
    
    
}
#Preview {
    CameraFullView()
}
