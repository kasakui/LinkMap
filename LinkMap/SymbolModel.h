//
//  SymbolModel.h
//  LinkMap
//
//  Created by Suteki(67111677@qq.com) on 4/8/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SymbolModel : NSObject
/// 二进制库名
@property (nonatomic, copy) NSString *libName;
/// 类名
@property (nonatomic, copy) NSString *className;

@end
