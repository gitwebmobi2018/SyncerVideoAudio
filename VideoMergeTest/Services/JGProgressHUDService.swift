//
//  JGProgressHUDService.swift
//  VideoMergeTest
//
//  Created by Ivan on 12/11/18.
//  Copyright © 2018 Ivan. All rights reserved.
//

import Foundation
import JGProgressHUD

class JGProgressHUDService {
    private var HUD : JGProgressHUD!
    
    init() {
        HUD = JGProgressHUD()
    }
    
    func showHUD(_ view: UIView) {
        self.HUD.show(in: view)
    }
    
    func hideHUD() {
        if self.HUD.isVisible {
            self.HUD.dismiss()
        }
    }
}
