//
//  ViewController.m
//  LinkMap
//
//  Created by Suteki(67111677@qq.com) on 4/8/16.
//  Copyright © 2016 Apple. All rights reserved.
//

#import "ViewController.h"
#import "SymbolModel.h"

@interface ViewController()

@property (weak) IBOutlet NSTextField *filePathField;//显示选择的文件路径
@property (weak) IBOutlet NSProgressIndicator *indicator;//指示器
@property (weak) IBOutlet NSTextField *searchField;

@property (weak) IBOutlet NSScrollView *contentView;//分析的内容
@property (unsafe_unretained) IBOutlet NSTextView *contentTextView;
@property (weak) IBOutlet NSButton *groupButton;


@property (strong) NSURL *linkMapFileURL;
@property (strong) NSString *linkMapContent;

@property (strong) NSURL *comLinkMapFileURL;
@property (strong) NSString *comLinkMapContent;
@property (weak) IBOutlet NSTextField *compareFilePathField;

@property (strong) NSMutableString *result;//分析的结果

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.indicator.hidden = YES;
    
    _contentTextView.editable = NO;
    
    _contentTextView.string = @"使用方式：\n\
    1.在XCode中开启编译选项Write Link Map File \n\
    XCode -> Project -> Build Settings -> 把Write Link Map File选项设为yes，并指定好linkMap的存储位置 \n\
    2.工程编译完成后，在编译目录里找到Link Map文件（txt类型） \n\
    默认的文件地址：~/Library/Developer/Xcode/DerivedData/XXX-xxxxxxxxxxxxx/Build/Intermediates/XXX.build/Debug-iphoneos/XXX.build/ \n\
    3.回到本应用，点击“选择文件”，打开Link Map文件  \n\
    4.点击“开始”，解析Link Map文件 \n\
    5.点击“输出文件”，得到解析后的Link Map文件 \n\
    6. * 输入需忽略，然后点击“开始”。实现忽略功能 \n\
    7. * 勾选“具体到函数（默认到类名）”，然后点击“开始”。实现对不同库的目标文件进行分组";
}

- (IBAction)chooseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.resolvesAliases = NO;
    panel.canChooseFiles = YES;
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSURL *document = [[panel URLs] objectAtIndex:0];
            _filePathField.stringValue = document.path;
            self.linkMapFileURL = document;
        }
    }];
}

- (IBAction)chooseCompareFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.resolvesAliases = NO;
    panel.canChooseFiles = YES;
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSURL *document = [[panel URLs] objectAtIndex:0];
            _compareFilePathField.stringValue = document.path;
            self.comLinkMapFileURL = document;
        }
    }];
}

- (IBAction)analyze:(id)sender {
    if (!_linkMapFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[_linkMapFileURL path] isDirectory:nil]) {
        [self showAlertWithText:@"请选择正确的Link Map文件路径"];
        return;
    }
    
    if (!_comLinkMapFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[_comLinkMapFileURL path] isDirectory:nil]) {
        [self showAlertWithText:@"请选择正确对比的Link Map文件路径"];
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *content = [NSString stringWithContentsOfURL:_linkMapFileURL encoding:NSMacOSRomanStringEncoding error:nil];
        NSString *compareContent = [NSString stringWithContentsOfURL:_comLinkMapFileURL encoding:NSMacOSRomanStringEncoding error:nil];
        if (![self checkContent:content] || ![self checkContent:compareContent]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showAlertWithText:@"Link Map文件格式有误"];
            });
            return ;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.indicator.hidden = NO;
            [self.indicator startAnimation:self];
            
        });
        
        NSArray *symbolArray = [self symbolMapFromContent:content];
        NSMutableSet *set1 = [NSMutableSet setWithArray:symbolArray];
        
        NSArray *symbolArray2 = [self symbolMapFromContent:compareContent];
        NSMutableSet *set2 = [NSMutableSet setWithArray:symbolArray2];
        
        [set1 intersectSet:set2];
                
        [self buildResultWithSymbols:set1.allObjects];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.contentTextView.string = _result;
            self.indicator.hidden = YES;
            [self.indicator stopAnimation:self];
            
        });
    });
}

- (NSArray *)symbolMapFromContent:(NSString *)content {
    NSMutableArray *symbolArray = [NSMutableArray array];
    // 符号文件列表
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    
    BOOL reachFiles = NO;
    BOOL reachSymbols = NO;
    BOOL reachSections = NO;
    
    for(NSString *line in lines) {
        if([line hasPrefix:@"#"]) {
            if([line hasPrefix:@"# Object files:"])
                reachFiles = YES;
            else if ([line hasPrefix:@"# Sections:"])
                reachSections = YES;
            else if ([line hasPrefix:@"# Symbols:"])
                reachSymbols = YES;
        } else {
            if(reachFiles == YES && reachSections == YES && reachSymbols == YES) {
                __block NSControlStateValue groupButtonState;
                dispatch_sync(dispatch_get_main_queue(), ^{
                    groupButtonState = _groupButton.state;
                });
                NSRange range = [line rangeOfString:@"]"];
                if(range.location != NSNotFound) {
                    NSString *classFuncName = [line substringFromIndex:range.location+2];
                    if (groupButtonState == NSControlStateValueOn) {
                        // 具体到函数
                        if (([classFuncName hasPrefix:@"-["]) || ([classFuncName hasPrefix:@"+["])) {
                            [symbolArray addObject:classFuncName];
                        }
                    } else {
                        // 只到类名
                        if ([classFuncName containsString:@"_OBJC_CLASS_$_"]) {
                            NSString *className = [classFuncName stringByReplacingOccurrencesOfString:@"_OBJC_CLASS_$_" withString:@""];
                            [symbolArray addObject:className];
                        }
                    }
                }
            }
        }
    }
    return symbolArray.copy;
}

- (void)buildResultWithSymbols:(NSArray *)symbols {
    self.result = [@"相同的文件名称\r\n\r\n" mutableCopy];
    
    for(NSString *symbol in symbols) {
        [_result appendFormat:@"%@\t\r\n",symbol];
    }
}

- (IBAction)ouputFile:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:YES];
    [panel setResolvesAliases:NO];
    [panel setCanChooseFiles:NO];
    
    [panel beginWithCompletionHandler:^(NSInteger result) {
        if (result == NSFileHandlingPanelOKButton) {
            NSURL*  theDoc = [[panel URLs] objectAtIndex:0];
            NSMutableString *content =[[NSMutableString alloc]initWithCapacity:0];
            [content appendString:[theDoc path]];
            [content appendString:@"/linkMapCompareResult.txt"];
            [_result writeToFile:content atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }];
}

- (BOOL)checkContent:(NSString *)content {
    NSRange objsFileTagRange = [content rangeOfString:@"# Object files:"];
    if (objsFileTagRange.length == 0) {
        return NO;
    }
    NSString *subObjsFileSymbolStr = [content substringFromIndex:objsFileTagRange.location + objsFileTagRange.length];
    NSRange symbolsRange = [subObjsFileSymbolStr rangeOfString:@"# Symbols:"];
    if ([content rangeOfString:@"# Path:"].length <= 0||objsFileTagRange.location == NSNotFound||symbolsRange.location == NSNotFound) {
        return NO;
    }
    return YES;
}

- (void)showAlertWithText:(NSString *)text {
    NSAlert *alert = [[NSAlert alloc]init];
    alert.messageText = text;
    [alert addButtonWithTitle:@"确定"];
    [alert beginSheetModalForWindow:[NSApplication sharedApplication].windows[0] completionHandler:^(NSModalResponse returnCode) {
    }];
}

@end
