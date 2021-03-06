#import "UIImagePickerManager.h"
#import "RCTConvert.h"

@interface UIImagePickerManager ()

@property (nonatomic, strong) UIActionSheet *sheet;
@property (nonatomic, strong) UIImagePickerController *picker;
@property (nonatomic, strong) RCTResponseSenderBlock callback;
@property (nonatomic, strong) NSDictionary *defaultOptions;
@property (nonatomic, retain) NSMutableDictionary *options;

@end

@implementation UIImagePickerManager

RCT_EXPORT_MODULE();

- (instancetype)init {

    if (self = [super init]) {

        self.defaultOptions = @{
            @"title": @"Select a Photo",
            @"cancelButtonTitle": @"Cancel",
            @"takePhotoButtonTitle": @"Take Photo...",
            @"chooseFromLibraryButtonTitle": @"Choose from Library...",
            @"returnBase64Image" : @NO, // Only return base64 encoded version of the image
            @"returnIsVertical" : @NO, // If returning base64 image, return the orientation too
            @"quality" : @0.2 // 1.0 best to 0.0 worst
        };
    }

    return self;
}

RCT_EXPORT_METHOD(showImagePicker:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    self.callback = callback; // Save the callback so we can use it from the delegate methods
    self.options = [NSMutableDictionary dictionaryWithDictionary:self.defaultOptions]; // Set default options
    for (NSString *key in options.keyEnumerator) { // Replace default options
        [self.options setValue:options[key] forKey:key];
    }
    self.sheet = [[UIActionSheet alloc] initWithTitle:[self.options valueForKey:@"title"] delegate:self cancelButtonTitle:[self.options valueForKey:@"cancelButtonTitle"] destructiveButtonTitle:nil otherButtonTitles:[self.options valueForKey:@"takePhotoButtonTitle"], [self.options valueForKey:@"chooseFromLibraryButtonTitle"], nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
        [self.sheet showInView:root.view];
    });
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 2) { // Cancel
        self.callback(@[@"cancel"]); // Return callback for 'cancel' action (if is required)
        return;
    }

    self.picker = [[UIImagePickerController alloc] init];
    self.picker.modalPresentationStyle = UIModalPresentationCurrentContext;
    self.picker.delegate = self;

    if (buttonIndex == 0) { // Take photo
        // Will crash if we try to use camera on the simulator
#if TARGET_IPHONE_SIMULATOR
        NSLog(@"Camera not available on simulator");
        return;
#else
        self.picker.sourceType = UIImagePickerControllerSourceTypeCamera;
#endif
    }
    else if (buttonIndex == 1) { // Choose from library
        self.picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }

    UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    dispatch_async(dispatch_get_main_queue(), ^{
        [root presentViewController:self.picker animated:YES completion:nil];
    });

}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:nil];
    });

    /* Getting all bools together */
    BOOL BASE64 = [[self.options valueForKey:@"returnBase64Image"] boolValue];
    BOOL returnOrientation = [self.options[@"returnIsVertical"] boolValue];

    /* Picked Image */
    UIImage *image = [info objectForKey:UIImagePickerControllerOriginalImage];

    /* If not Base64 then return URL */
    if (!BASE64) {

        if (self.picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
            if (image != nil)
            {
                /* creating a temp url to be passed */
                NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                     NSUserDomainMask, YES);
                NSString *ImageUUID = [[NSUUID UUID] UUIDString];
                NSString *ImageName = [ImageUUID stringByAppendingString:@".jpg"];
                NSString *documentsDirectory = [paths objectAtIndex:0];

                // This will be the URL
                NSString* path = [documentsDirectory stringByAppendingPathComponent:ImageName];

                NSData *data = UIImageJPEGRepresentation(image, [[self.options valueForKey:@"quality"] floatValue]);

                /* Write to the disk */
                [data writeToFile:path atomically:YES];

                self.callback(@[@"uri", path]);
            }
        }
        else {
            // Get URL for the image fetched from the Photos
            NSString *imageURL = [((NSURL*)info[UIImagePickerControllerReferenceURL]) absoluteString];
            if (imageURL) { // Image chosen from library, send
                self.callback(@[@"uri", imageURL]);
            }
        }
    }
    else {
        UIImage *image = info[UIImagePickerControllerOriginalImage];

        if ([self.options objectForKey:@"targetWidth"] && [self.options objectForKey:@"targetHeight"]) {
            CGSize targetSize = CGSizeMake([[self.options valueForKey:@"targetWidth"] floatValue], [[self.options valueForKey:@"targetHeight"] floatValue]);
            image = [self scaleImage:image toSize:targetSize];
        }

        NSData *imageData = UIImageJPEGRepresentation(image, [[self.options valueForKey:@"quality"] floatValue]);
        NSString *dataString = [imageData base64EncodedStringWithOptions:0];

        if (returnOrientation) { // Return image orientation if desired
            NSString *vertical = (image.size.width < image.size.height) ? @"true" : @"false";
            self.callback(@[@"data", dataString, vertical]);
        }
        else {
            self.callback(@[@"data", dataString]);
        }
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:nil];
    });

    self.callback(@[@"cancel"]);
}

- (UIImage*)scaleImage: (UIImage*)sourceImage toSize:(CGSize)targetSize
{
  UIImage* newImage = nil;
  CGSize imageSize = sourceImage.size;
  CGFloat width = imageSize.width;
  CGFloat height = imageSize.height;
  CGFloat targetWidth = targetSize.width;
  CGFloat targetHeight = targetSize.height;
  CGFloat scaleFactor = 0.0;
  CGSize scaledSize = targetSize;

  if (CGSizeEqualToSize(imageSize, targetSize) == NO) {
    CGFloat widthFactor = targetWidth / width;
    CGFloat heightFactor = targetHeight / height;

    // opposite comparison to imageByScalingAndCroppingForSize in order to contain the image within the given bounds
    if (widthFactor > heightFactor) {
      scaleFactor = heightFactor; // scale to fit height
    } else {
      scaleFactor = widthFactor; // scale to fit width
    }
    scaledSize = CGSizeMake(MIN(width * scaleFactor, targetWidth), MIN(height * scaleFactor, targetHeight));
  }

  // If the pixels are floats, it causes a white line in iOS8 and probably other versions too
  scaledSize.width = (int)scaledSize.width;
  scaledSize.height = (int)scaledSize.height;

  UIGraphicsBeginImageContext(scaledSize); // this will resize

  [sourceImage drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];

  newImage = UIGraphicsGetImageFromCurrentImageContext();
  if (newImage == nil) {
    NSLog(@"could not scale image");
  }

  // pop the context to get back to the default
  UIGraphicsEndImageContext();
  return newImage;
}

@end
