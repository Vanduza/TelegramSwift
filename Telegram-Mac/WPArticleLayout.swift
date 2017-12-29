//
//  WPArticleLayout.swift
//  Telegram-Mac
//
//  Created by keepcoder on 18/10/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TelegramCoreMac
import PostboxMac
import TGUIKit
class WPArticleLayout: WPLayout {
    
    
    var imageSize:NSSize?
    var contrainedImageSize:NSSize = NSMakeSize(54, 54)
    var smallThumb:Bool = true
    var imageArguments:TransformImageArguments?
    
    private(set) var duration:(TextNodeLayout, TextNode)?
    private let durationAttributed:NSAttributedString?
    override init(with content: TelegramMediaWebpageLoadedContent, account:Account, chatInteraction:ChatInteraction, parent:Message, fontSize: CGFloat, presentation: WPLayoutPresentation) {
        if let duration = content.duration {
            self.durationAttributed = .initialize(string: String.durationTransformed(elapsed: duration), color: .white, font: .normal(.text))
        } else {
            durationAttributed = nil
        }
        super.init(with: content, account:account, chatInteraction: chatInteraction, parent:parent, fontSize: fontSize, presentation: presentation)
        
        
        
        if let image = content.image {
            
            if let dimensions = largestImageRepresentation(image.representations)?.dimensions {
                imageSize = dimensions
            }
           
        }
        
    }
    
    private let mediaTypes:[String] = ["photo","video"]
    private let fullSizeSites:[String] = ["instagram","twitter"]
    
    var isFullImageSize: Bool {
        let website = content.websiteName?.lowercased()
        if let type = content.type, mediaTypes.contains(type) || (fullSizeSites.contains(website ?? "") || content.instantPage != nil) || content.text == nil  {
            if let imageSize = imageSize {
                if imageSize.width < 200 {
                    return false
                }
            }
            return true
        }
        return content.text == nil || content.text!.trimmed.isEmpty
    }
    
    override func measure(width: CGFloat) {
        super.measure(width: width)
        
        var contentSize:NSSize = NSMakeSize(width - insets.left, 0)
        
        if let imageSize = imageSize, isFullImageSize {
            contrainedImageSize = imageSize.fitted(NSMakeSize(min(width - insets.left, 320), 300))
            textLayout?.cutout = nil
            smallThumb = false
            contentSize.height += contrainedImageSize.height
            contentSize.width = contrainedImageSize.width
            if textLayout != nil {
                contentSize.height += 6
            }
        } else {
            if let _ = imageSize {
                contrainedImageSize = NSMakeSize(54, 54)
                textLayout?.cutout = TextViewCutout(position: .TopRight, size: NSMakeSize(contrainedImageSize.width + 16, contrainedImageSize.height + 10))
            }
        }
        
        if let durationAttributed = durationAttributed {
            duration = TextNode.layoutText(durationAttributed, nil, 1, .end, NSMakeSize(contentSize.width, .greatestFiniteMagnitude), nil, false, .center)
        }

        textLayout?.measure(width: contentSize.width)
        
        if let textLayout = textLayout {
            
            contentSize.height += textLayout.layoutSize.height
            
            if textLayout.cutout != nil {
                
                contentSize.height = max(content.image != nil ? contrainedImageSize.height : 0,contentSize.height)
                contentSize.width = min(max(textLayout.layoutSize.width, (siteName?.0.size.width ?? 0) + contrainedImageSize.width), width - insets.left)
            } else if imageSize == nil {
                contentSize.width = max(textLayout.layoutSize.width, (siteName?.0.size.width ?? 0))
            }
        }
        
        if let imageSize = imageSize {
            let imageArguments = TransformImageArguments(corners: ImageCorners(radius: 4.0), imageSize: imageSize, boundingSize: contrainedImageSize, intrinsicInsets: NSEdgeInsets())
            
            if imageArguments != self.imageArguments {
                self.imageArguments = imageArguments
            }
        } else {
            self.imageArguments = nil
        }
       
        
        
        
        layout(with :contentSize)
    }
    
}
