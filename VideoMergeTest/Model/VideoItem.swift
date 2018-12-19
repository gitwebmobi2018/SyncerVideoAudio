//
//  VideoItem.swift
//  VideoMergeTest
//
//  Created by gitwebmobi2018 on 12/11/18.
//  Copyright © 2018 gitwebmobi2018. All rights reserved.
//

import Foundation
import UIKit

class VideoItem: NSObject, NSCoding {
    
    var fileName            : String?
    var previewImg          : UIImage?
    
    override init() {
        
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(self.fileName, forKey:"fileName")
        aCoder.encode(self.previewImg, forKey:"previewImg")
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.fileName = aDecoder.decodeObject(forKey: "fileName") as? String
        self.previewImg = aDecoder.decodeObject(forKey: "previewImg") as? UIImage
    }
    
}
