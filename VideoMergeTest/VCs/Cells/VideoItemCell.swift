//
//  VideoItemCell.swift
//  VideoMergeTest
//
//  Created by gitwebmobi2018 on 12/11/18.
//  Copyright © 2018 gitwebmobi2018. All rights reserved.
//

import UIKit

class VideoItemCell: UITableViewCell {

    @IBOutlet weak var previewImgView: UIImageView!
    @IBOutlet weak var descriptionLbl: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}

extension VideoItemCell {
    
    func set(videoItem item: VideoItem) {
        previewImgView.image = item.previewImg
        descriptionLbl.text = """
        \(item.fileName ?? "No name")
        """
    }
    
}
