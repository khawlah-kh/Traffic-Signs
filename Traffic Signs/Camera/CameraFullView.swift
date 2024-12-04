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
    var body: some View {
        ZStack{
            CameraView()
                .edgesIgnoringSafeArea(.all)
        }        
    }
}
    

#Preview {
    CameraFullView()
}
