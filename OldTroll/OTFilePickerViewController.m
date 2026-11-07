//
//  OTFilePickerViewController.m
//  OldTroll
//

#import "OTFilePickerViewController.h"
#import "OTAlert.h"
#import "OTCompat.h"
#import "OTNavigationController.h"

@interface OTFilePickerViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *items;

@end

@implementation OTFilePickerViewController

- (instancetype)initWithPath:(NSString *)path {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _currentPath = [path copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *displayName = [self.currentPath lastPathComponent];
    self.title = displayName.length > 0 ? displayName : @"/";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self
                                                                                          action:@selector(cancelTapped:)];

    [self loadItems];
}

- (void)cancelTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Loading

- (void)loadItems {
    NSError *error = nil;
    NSArray *children = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.currentPath error:&error];
    if (children == nil) {
        [OTAlert showWithTitle:@"Cannot open directory"
                       message:error.localizedDescription ?: self.currentPath
                  cancelButton:@"OK"
                       buttons:nil
                       handler:nil];
        if (self.navigationController.viewControllers.count > 1) {
            [self.navigationController popViewControllerAnimated:YES];
        }
        return;
    }

    NSMutableArray *items = [NSMutableArray array];
    for (NSString *child in children) {
        if ([child hasPrefix:@"."]) {
            continue;
        }
        NSString *path = [self.currentPath stringByAppendingPathComponent:child];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
            continue;
        }
        if (!isDirectory && ![[[child pathExtension] lowercaseString] isEqualToString:@"ipa"]) {
            continue;
        }
        [items addObject:@{@"name": child, @"path": path, @"isDir": @(isDirectory)}];
    }

    [items sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        BOOL leftDir = [left[@"isDir"] boolValue];
        BOOL rightDir = [right[@"isDir"] boolValue];
        if (leftDir != rightDir) {
            return leftDir ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
    self.items = items;
    [self.tableView reloadData];
}

- (NSString *)formattedSizeForPath:(NSString *)path {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    unsigned long long bytes = [attributes[NSFileSize] unsignedLongLongValue];
    if (bytes < 1024) {
        return [NSString stringWithFormat:@"%llu B", bytes];
    }
    if (bytes < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f KB", (double)bytes / 1024.0];
    }
    return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"FileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    cell.textLabel.text = item[@"name"];
    if ([item[@"isDir"] boolValue]) {
        cell.detailTextLabel.text = @"Folder";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.textColor = [UIColor blackColor];
    } else {
        cell.detailTextLabel.text = [self formattedSizeForPath:item[@"path"]];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:0.35 blue:0.85 alpha:1.0];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    NSString *path = item[@"path"];

    if ([item[@"isDir"] boolValue]) {
        OTFilePickerViewController *next = [[OTFilePickerViewController alloc] initWithPath:path];
        next.delegate = self.delegate;
        [self.navigationController pushViewController:next animated:YES];
        return;
    }

    if ([self.delegate respondsToSelector:@selector(filePicker:didSelectFileAtPath:)]) {
        [self.delegate filePicker:self didSelectFileAtPath:path];
    }
}

@end
