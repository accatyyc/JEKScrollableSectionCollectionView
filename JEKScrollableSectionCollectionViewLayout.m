//
//  JEKScrollableSectionCollectionViewLayout.m
//  Example Project
//
//  Created by Joel Ekström on 2018-07-19.
//  Copyright © 2018 Joel Ekström. All rights reserved.
//

#import "JEKScrollableSectionCollectionViewLayout.h"
#import <objc/runtime.h>

static NSString * const JEKScrollableCollectionViewLayoutScrollViewKind = @"JEKScrollableCollectionViewLayoutScrollViewKind";
NSString * const JEKCollectionElementKindSectionBackground = @"JEKCollectionElementKindSectionBackground";

@class JEKScrollableSectionInfo, JEKScrollableSectionDecorationView;

@interface JEKScrollableSectionDecorationViewLayoutAttributes : UICollectionViewLayoutAttributes
@property (nonatomic, strong) JEKScrollableSectionInfo *section;
@end

@interface JEKScrollableSectionInfo : NSObject
@property (nonatomic, weak) JEKScrollableSectionCollectionViewLayout *layout;
@property (nonatomic, weak) JEKScrollableSectionDecorationView *currentDecorationView; // Will be set when only when section is visible
@property (nonatomic, assign) CGPoint offset;
@property (nonatomic, assign) CGFloat interItemSpacing;
@property (nonatomic, assign) UIEdgeInsets insets;
@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, assign) CGFloat collectionViewWidth;
@property (nonatomic, strong) NSMutableArray<NSValue *> *itemSizes;
@property (nonatomic, assign) NSUInteger numberOfItems;
@property (nonatomic, assign) CGSize headerSize;
@property (nonatomic, assign) CGSize footerSize;
@property (nonatomic, assign) BOOL needsLayout;
@property (nonatomic, assign) BOOL shouldUseFlowLayout;
- (void)prepareLayout;

@property (nonatomic, readonly) CGRect frame; // Relative frame of the section in the collection view
@property (nonatomic, readonly) CGRect bounds; // The rect containing all elements of the section (items, header, footer), starting at (0,0)
@property (nonatomic, readonly) CGRect itemFrame; // The rect containing the items but not headers and footers
@property (nonatomic, readonly) JEKScrollableSectionDecorationViewLayoutAttributes *decorationViewAttributes;
@property (nonatomic, readonly) UICollectionViewLayoutAttributes *headerViewAttributes;
@property (nonatomic, readonly) UICollectionViewLayoutAttributes *footerViewAttributes;
@property (nonatomic, readonly) UICollectionViewLayoutAttributes *backgroundViewAttributes;

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesIntersectingRect:(CGRect)rect;
- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndex:(NSUInteger)index;
@end

@interface JEKScrollableSectionLayoutInvalidationContext : UICollectionViewLayoutInvalidationContext
@property (nonatomic, strong) JEKScrollableSectionInfo *invalidatedSection;
@property (nonatomic, assign) BOOL invalidateCollectionViewWidth;
@end

@interface JEKScrollableSectionCollectionViewLayout() <UIScrollViewDelegate>
@property (nonatomic, assign) CGSize contentSize;
@property (nonatomic, strong) NSArray<JEKScrollableSectionInfo *> *sections;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *offsetCache;
@property (nonatomic, weak) id<UICollectionViewDelegateFlowLayout> delegate;
@end

@interface JEKScrollableSectionDecorationView : UICollectionReusableView <UIGestureRecognizerDelegate>
@property (nonatomic, readonly, strong) UIScrollView *scrollView;
@property (nonatomic, strong) JEKScrollableSectionInfo *section;
@end

@interface JEKScrollView : UIScrollView @end

@implementation JEKScrollableSectionCollectionViewLayout

- (instancetype)init
{
    if (self = [super init]) {
        [self configure];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self configure];
    }
    return self;
}

- (void)configure
{
    [self registerClass:JEKScrollableSectionDecorationView.class forDecorationViewOfKind:JEKScrollableCollectionViewLayoutScrollViewKind];
    self.offsetCache = [NSMutableDictionary new];
    self.defaultScrollViewConfiguration = [JEKScrollViewConfiguration new];
}

- (void)setShowsHorizontalScrollIndicators:(BOOL)showsHorizontalScrollIndicators
{
    self.defaultScrollViewConfiguration.showsHorizontalScrollIndicator = showsHorizontalScrollIndicators;
}

+ (Class)invalidationContextClass
{
    return JEKScrollableSectionLayoutInvalidationContext.class;
}

- (BOOL)flipsHorizontallyInOppositeLayoutDirection
{
    return YES;
}

- (void)prepareLayout
{
    [super prepareLayout];

    if (self.sections == nil) {
        NSMutableArray<JEKScrollableSectionInfo *> *sections = [NSMutableArray new];
        NSInteger numberOfSections = [self.collectionView numberOfSections];

        for (NSInteger section = 0; section < numberOfSections; ++section) {
            JEKScrollableSectionInfo *sectionInfo = [JEKScrollableSectionInfo new];
            sectionInfo.layout = self;
            sectionInfo.index = section;
            sectionInfo.collectionViewWidth = self.collectionView.frame.size.width;
            sectionInfo.needsLayout = YES;
            [sections addObject:sectionInfo];
        }
        self.sections = [sections copy];
    }

    [self layoutSectionsIfNeeded];
}

- (void)layoutSectionsIfNeeded
{
    __block CGFloat yOffset = 0.0;
    [self.sections enumerateObjectsUsingBlock:^(JEKScrollableSectionInfo *section, NSUInteger index, BOOL *stop) {
        if (section.needsLayout) {
            section.insets = [self sectionInsetsForSection:index];
            section.interItemSpacing = [self interItemSpacingForSection:index];
            section.headerSize = [self headerSizeForSection:index];
            section.footerSize = [self footerSizeForSection:index];
            section.numberOfItems = [self.collectionView numberOfItemsInSection:index];
            section.shouldUseFlowLayout = [self shouldUseFlowLayoutInSection:index];
            NSMutableArray<NSValue *> *itemSizes = [NSMutableArray new];
            for (NSInteger item = 0; item < section.numberOfItems; ++item) {
                CGSize itemSize = [self itemSizeForIndexPath:[NSIndexPath indexPathForItem:item inSection:section.index]];
                [itemSizes addObject:[NSValue valueWithCGSize:itemSize]];
            }
            section.itemSizes = itemSizes;
            [section prepareLayout];
            section.offset = CGPointMake(self.offsetCache[@(section.index)].floatValue, yOffset);
        }
        yOffset += CGRectGetHeight(section.frame);
    }];
    self.contentSize = CGSizeMake(self.collectionView.frame.size.width, yOffset);
}

- (void)invalidateLayoutWithContext:(JEKScrollableSectionLayoutInvalidationContext *)context
{
    [super invalidateLayoutWithContext:context];

    if (context.invalidateEverything) {
        self.sections = nil;
        return;
    }

    if (context.invalidateCollectionViewWidth) {
        for (JEKScrollableSectionInfo *section in self.sections) {
            section.needsLayout = YES;
            section.collectionViewWidth = self.collectionView.frame.size.width;
        }
    }

    if (context.invalidateDataSourceCounts) {
        for (JEKScrollableSectionInfo *section in self.sections) {
            section.needsLayout = YES;
        }
    }

    if (context.invalidatedSection) {
        CGPoint offset = context.invalidatedSection.offset;
        offset.x = self.offsetCache[@([self.sections indexOfObject:context.invalidatedSection])].floatValue;
        context.invalidatedSection.offset = offset;
    }

    self.contentSize = CGSizeMake(self.collectionView.frame.size.width, self.contentSize.height);
}

- (CGSize)collectionViewContentSize
{
    return self.contentSize;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self.sections[indexPath.section] layoutAttributesForItemAtIndex:indexPath.item];
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    JEKScrollableSectionInfo *section = self.sections[indexPath.section];
    if (elementKind == UICollectionElementKindSectionHeader) {
        return section.headerViewAttributes;
    } else if (elementKind == UICollectionElementKindSectionFooter) {
        return section.footerViewAttributes;
    } else if (elementKind == JEKCollectionElementKindSectionBackground) {
        return section.backgroundViewAttributes;
    } else {
        return nil;
    }
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    if (elementKind == JEKScrollableCollectionViewLayoutScrollViewKind) {
        return self.sections[indexPath.section].decorationViewAttributes;
    }
    return nil;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSMutableArray *visibleAttributes = [NSMutableArray new];
    BOOL anyVisibleSectionFound = NO;
    for (JEKScrollableSectionInfo *section in self.sections) {
        NSArray *intersectingAttributes = [section layoutAttributesIntersectingRect:rect];
        if (intersectingAttributes.count > 0) {
            anyVisibleSectionFound = YES;
            [visibleAttributes addObjectsFromArray:intersectingAttributes];
            if (self.showsSectionBackgrounds) {
                [visibleAttributes addObject:section.backgroundViewAttributes];
            }
        }

        // Optimization: If we have seen previously intersecting items but the current one
        // doesn't intersect, we can break to avoid extra work since they are enumerated
        // in visible order.
        // TODO: Find the first visible section/items using binary search instead of enumerating
        // from first index. Right now, if the visible bounds are on section 3000, then 2999 sections will be enumerated
        // but not visible.
        else if (anyVisibleSectionFound) { break; }
    }
    return visibleAttributes;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    return newBounds.size.width != self.contentSize.width;
}

- (UICollectionViewLayoutInvalidationContext *)invalidationContextForBoundsChange:(CGRect)newBounds
{
    JEKScrollableSectionLayoutInvalidationContext *context = (JEKScrollableSectionLayoutInvalidationContext *)[super invalidationContextForBoundsChange:newBounds];
    context.invalidateCollectionViewWidth = YES;
    return context;
}

/**
 Offsets a horizontal section to accomodate for scrollToItemAtIndexPath:.
 This function has to have special handling since UICollectionView doesn't expect
 that there can be cells outside the scrollable bounds.
 */
- (void)scrollToItemAtIndexPath:(NSIndexPath *)targetIndexPath scrollPosition:(UICollectionViewScrollPosition)scrollPosition animated:(BOOL)animated
{
    JEKScrollableSectionInfo *section = self.sections[targetIndexPath.section];

    // We can't offset a flow layout section horizontally
    if (section.shouldUseFlowLayout) {
        return;
    }

    CGRect itemFrame = [section layoutAttributesForItemAtIndex:targetIndexPath.item].frame;

    CGRect targetFrame = itemFrame;
    if (scrollPosition & UICollectionViewScrollPositionCenteredHorizontally) {
        targetFrame.origin.x = self.collectionViewContentSize.width / 2.0 - targetFrame.size.width / 2.0;
    } else if (scrollPosition & UICollectionViewScrollPositionRight) {
        targetFrame.origin.x = (self.collectionViewContentSize.width - targetFrame.size.width) - 10.0;
    } else if (scrollPosition & UICollectionViewScrollPositionLeft) {
        targetFrame.origin.x = 10.0;
    }

    CGFloat horizontalOffsetDifference = targetFrame.origin.x - itemFrame.origin.x;
    CGFloat newSectionOffset = section.offset.x - horizontalOffsetDifference;
    [self setHorizontalOffset:newSectionOffset forSection:section animated:animated];
}

- (void)setHorizontalOffset:(CGFloat)offset forSectionAtIndex:(NSUInteger)index animated:(BOOL)animated
{
    [self setHorizontalOffset:offset forSection:self.sections[index] animated:animated];
}

- (void)setHorizontalOffset:(CGFloat)offset forSection:(JEKScrollableSectionInfo *)section animated:(BOOL)animated
{
    self.offsetCache[@(section.index)] = @(-offset);

    // If the section is visible, we can use its scrollview to handle the animation for us
    if (animated && section.currentDecorationView) {
        [section.currentDecorationView.scrollView setContentOffset:CGPointMake(offset, 0) animated:YES];
    }

    // Otherwise, invalidate the layout
    else {
        JEKScrollableSectionLayoutInvalidationContext *invalidationContext = [JEKScrollableSectionLayoutInvalidationContext new];
        invalidationContext.invalidatedSection = section;
        [self invalidateLayoutWithContext:invalidationContext];
    }
}

#define DELEGATE_RESPONDS_TO_SELECTOR(SEL) ([self.collectionView.delegate conformsToProtocol:@protocol(JEKCollectionViewDelegateScrollableSectionLayout)] &&\
                                            [self.collectionView.delegate respondsToSelector:SEL])
#define DELEGATE (id<JEKCollectionViewDelegateScrollableSectionLayout>)self.collectionView.delegate

- (BOOL)shouldUseFlowLayoutInSection:(NSInteger)section
{
    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:shouldUseFlowLayoutInSection:))) {
        return [DELEGATE collectionView:self.collectionView layout:self shouldUseFlowLayoutInSection:section];
    }
    return NO;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    NSUInteger section = scrollView.tag;
    [self setHorizontalOffset:scrollView.contentOffset.x forSectionAtIndex:section animated:NO];

    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:section:didScrollToOffset:))) {
        [DELEGATE collectionView:self.collectionView layout:self section:section didScrollToOffset:scrollView.contentOffset.x];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:sectionWillBeginDragging:))) {
        [DELEGATE collectionView:self.collectionView layout:self sectionWillBeginDragging:scrollView.tag];
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{
    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:sectionWillEndDragging:withVelocity:targetOffset:))) {
        [DELEGATE collectionView:self.collectionView layout:self sectionWillEndDragging:scrollView.tag withVelocity:velocity.x targetOffset:&targetContentOffset->x];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:sectionDidEndDragging:willDecelerate:))) {
        [DELEGATE collectionView:self.collectionView layout:self sectionDidEndDragging:scrollView.tag willDecelerate:decelerate];
    }
}

- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scrollView
{
    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:sectionWillBeginDecelerating:))) {
        [DELEGATE collectionView:self.collectionView layout:self sectionWillBeginDecelerating:scrollView.tag];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:sectionDidEndDecelerating:))) {
        [DELEGATE collectionView:self.collectionView layout:self sectionDidEndDecelerating:scrollView.tag];
    }
}

#pragma mark - Measurements

- (CGFloat)interItemSpacingForSection:(NSUInteger)section
{
    return [self.delegate respondsToSelector:@selector(collectionView:layout:minimumInteritemSpacingForSectionAtIndex:)] ? [self.delegate collectionView:self.collectionView layout:self minimumInteritemSpacingForSectionAtIndex:section] : self.minimumInteritemSpacing;
}

- (UIEdgeInsets)sectionInsetsForSection:(NSUInteger)section
{
    return [self.delegate respondsToSelector:@selector(collectionView:layout:insetForSectionAtIndex:)] ? [self.delegate collectionView:self.collectionView layout:self insetForSectionAtIndex:section] : self.sectionInset;
}

- (CGSize)headerSizeForSection:(NSUInteger)section
{
    return [self.delegate respondsToSelector:@selector(collectionView:layout:referenceSizeForHeaderInSection:)] ? [self.delegate collectionView:self.collectionView layout:self referenceSizeForHeaderInSection:section] : self.headerReferenceSize;
}

- (CGSize)footerSizeForSection:(NSUInteger)section
{
    return [self.delegate respondsToSelector:@selector(collectionView:layout:referenceSizeForFooterInSection:)] ? [self.delegate collectionView:self.collectionView layout:self referenceSizeForFooterInSection:section] : self.footerReferenceSize;
}

- (CGSize)itemSizeForIndexPath:(NSIndexPath *)indexPath
{
    return [self.delegate respondsToSelector:@selector(collectionView:layout:sizeForItemAtIndexPath:)] ? [self.delegate collectionView:self.collectionView layout:self sizeForItemAtIndexPath:indexPath] : self.itemSize;
}

- (JEKScrollViewConfiguration *)scrollViewConfigurationForSection:(NSUInteger)section
{
    JEKScrollViewConfiguration *configuration = self.defaultScrollViewConfiguration;
    if (DELEGATE_RESPONDS_TO_SELECTOR(@selector(collectionView:layout:scrollViewConfigurationForSection:))) {
        configuration = [DELEGATE collectionView:self.collectionView layout:self scrollViewConfigurationForSection:section] ?: configuration;
    }
    return configuration;
}

- (id<UICollectionViewDelegateFlowLayout>)delegate
{
    id delegate = self.collectionView.delegate;
    return [delegate conformsToProtocol:@protocol(UICollectionViewDelegateFlowLayout)] ? delegate : nil;
}

@end

@implementation JEKScrollableSectionDecorationView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        _scrollView = [[JEKScrollView alloc] initWithFrame:self.bounds];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scrollView.showsHorizontalScrollIndicator = YES;
        _scrollView.alwaysBounceVertical = NO;
        _scrollView.alwaysBounceHorizontal = YES;
        _scrollView.directionalLockEnabled = YES;
        [self addSubview:_scrollView];
        self.userInteractionEnabled = NO;
        [self addObserver:self forKeyPath:@"section.bounds" options:NSKeyValueObservingOptionNew context:nil];
    }
    return self;
}

- (void)dealloc
{
    [self removeObserver:self forKeyPath:@"section.bounds"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    // When items are inserted/deleted, we need to update the scroll view content size, so listen to
    // bounds changes within the section
    if ([keyPath isEqualToString:@"section.bounds"]) {
        self.scrollView.contentSize = self.section.itemFrame.size;
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)applyLayoutAttributes:(JEKScrollableSectionDecorationViewLayoutAttributes *)layoutAttributes
{
    [super applyLayoutAttributes:layoutAttributes];
    self.section = layoutAttributes.section;
    self.section.currentDecorationView = self;
    self.scrollView.tag = layoutAttributes.indexPath.section;
    [self applyScrollViewConfiguration:[self.section.layout scrollViewConfigurationForSection:layoutAttributes.indexPath.section]];
    [self.scrollView setContentOffset:CGPointMake(-layoutAttributes.section.offset.x, 0.0) animated:NO];
}

- (void)applyScrollViewConfiguration:(JEKScrollViewConfiguration *)configuration
{
    self.scrollView.bounces = configuration.bounces;
    self.scrollView.alwaysBounceHorizontal = configuration.alwaysBounceHorizontal;
    self.scrollView.showsHorizontalScrollIndicator = configuration.showsHorizontalScrollIndicator;
    self.scrollView.scrollIndicatorInsets = configuration.scrollIndicatorInsets;
    self.scrollView.indicatorStyle = configuration.indicatorStyle;
    self.scrollView.decelerationRate = configuration.decelerationRate;
    self.scrollView.pagingEnabled = configuration.isPagingEnabled;
    self.scrollView.scrollEnabled = configuration.isScrollEnabled;
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    if (self.superview) {
        UICollectionView *collectionView = (UICollectionView *)self.superview;
        self.scrollView.delegate = (JEKScrollableSectionCollectionViewLayout *)collectionView.collectionViewLayout;
        [collectionView addGestureRecognizer:self.scrollView.panGestureRecognizer];
        _scrollView.transform = [self shouldFlipLayoutDirection] ? CGAffineTransformMakeScale(-1.0, 1.0) : CGAffineTransformIdentity;
    } else {
        self.scrollView.delegate = nil;
        [self.scrollView.panGestureRecognizer.view removeGestureRecognizer:self.scrollView.panGestureRecognizer];
    }
}

- (BOOL)shouldFlipLayoutDirection
{
    if (@available(iOS 11.0, *)) {
        return self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    }
    return NO;
}

@end

@implementation JEKScrollView

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(nonnull UITouch *)touch
{
    JEKScrollableSectionDecorationView *decorationView = (JEKScrollableSectionDecorationView *)self.superview;
    if (CGRectContainsPoint(decorationView.frame, [touch locationInView:decorationView.superview])) {
        return YES;
    } else {
        // NOTE: This is a bugfix. When the collection view receives a touch it will pause the deceleration
        // of any scroll view that is currently scrolling - however the scroll view is never informed that it
        // is stopped, which makes its scrolling indicator stay visible forever. We make sure that the scroll view
        // knows that it is stopped by forcing a stop whenever anything else receives a touch.
        [self setContentOffset:self.contentOffset animated:NO];
        return NO;
    }
}

@end

@implementation JEKScrollableSectionDecorationViewLayoutAttributes

- (id)copyWithZone:(NSZone *)zone
{
    JEKScrollableSectionDecorationViewLayoutAttributes *copy = [super copyWithZone:zone];
    copy.section = self.section;
    return copy;
}

@end

@interface JEKScrollableSectionInfo()
@property (nonatomic, assign) CGRect bounds;
@property (nonatomic, strong) NSArray<NSValue *> *itemFrames;
@end

@implementation JEKScrollableSectionInfo

- (void)prepareLayout
{
    CGRect bounds = CGRectZero;
    bounds.size.width = self.insets.left;
    bounds.size.height = self.headerSize.height;
    NSMutableArray<NSValue *> *itemFrames = [NSMutableArray new];
    CGRect previousItemFrame = CGRectZero;
    for (NSUInteger item = 0; item < self.numberOfItems; ++item) {
        CGSize size = [self.itemSizes[item] CGSizeValue];
        CGRect frame;
        frame.size = size;

        CGFloat largestXOnExistingRow = CGRectGetMaxX(previousItemFrame) + (item == 0 ? 0.0 : self.interItemSpacing);
        if (self.shouldUseFlowLayout && (largestXOnExistingRow + frame.size.width) > (self.collectionViewWidth - self.insets.right)) {
            // Flowlayout and item won't fit - place it on a new row below
            frame.origin.x = self.insets.left;
            frame.origin.y = CGRectGetMaxY(bounds) + (item == 0 ? 0.0 : self.interItemSpacing);
        } else {
            // Not flow layout or it actually fits in the current flow layouted row
            frame.origin.x = (item == 0 ? self.insets.left : CGRectGetMaxX(previousItemFrame) + self.interItemSpacing);
            frame.origin.y = (item == 0 ? self.insets.top + self.headerSize.height : previousItemFrame.origin.y);
        }
        bounds = CGRectUnion(bounds, frame);
        [itemFrames addObject:[NSValue valueWithCGRect:frame]];
        previousItemFrame = frame;
    }
    bounds.size.width += self.insets.right;
    bounds.size.height += self.footerSize.height + self.insets.bottom;
    self.bounds = bounds;
    self.itemFrames = [itemFrames copy];
    self.needsLayout = NO;
}

- (CGRect)frame
{
    return CGRectOffset(self.bounds, self.offset.x, self.offset.y);
}

- (CGRect)itemFrame
{
    return UIEdgeInsetsInsetRect(self.frame, UIEdgeInsetsMake(self.headerSize.height + self.insets.top, 0.0, self.footerSize.height + self.insets.bottom, 0.0));
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndex:(NSUInteger)index
{
    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:index inSection:self.index]];
    attributes.frame = CGRectOffset(self.itemFrames[index].CGRectValue, self.offset.x, self.offset.y);
    return attributes;
}

- (UICollectionViewLayoutAttributes *)headerViewAttributes
{
    if (CGSizeEqualToSize(self.headerSize, CGSizeZero)) {
        return nil;
    }

    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader withIndexPath:[NSIndexPath indexPathForItem:0 inSection:self.index]];
    attributes.frame = CGRectMake(0.0, self.offset.y, self.collectionViewWidth, self.headerSize.height);
    return attributes;
}

- (UICollectionViewLayoutAttributes *)footerViewAttributes
{
    if (CGSizeEqualToSize(self.footerSize, CGSizeZero)) {
        return nil;
    }

    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionFooter withIndexPath:[NSIndexPath indexPathForItem:0 inSection:self.index]];
    CGRect sectionFrame = self.frame;
    attributes.frame = CGRectMake(0.0, CGRectGetMaxY(sectionFrame) - self.footerSize.height, self.collectionViewWidth, self.footerSize.height);
    return attributes;
}

- (UICollectionViewLayoutAttributes *)backgroundViewAttributes
{
    UICollectionViewLayoutAttributes *attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:JEKCollectionElementKindSectionBackground withIndexPath:[NSIndexPath indexPathForItem:0 inSection:self.index]];
    CGRect frame = [self frame];
    frame.origin.x = 0.0;
    frame.size.width = self.collectionViewWidth;
    attributes.frame = frame;
    attributes.zIndex = -99;
    return attributes;
}

- (JEKScrollableSectionDecorationViewLayoutAttributes *)decorationViewAttributes
{
    JEKScrollableSectionDecorationViewLayoutAttributes *attributes = [JEKScrollableSectionDecorationViewLayoutAttributes layoutAttributesForDecorationViewOfKind:JEKScrollableCollectionViewLayoutScrollViewKind withIndexPath:[NSIndexPath indexPathForItem:0 inSection:self.index]];
    CGRect frame = [self itemFrame];
    attributes.section = self;

    frame.origin.x = 0.0;
    frame.size.width = self.collectionViewWidth;

    attributes.frame = frame;
    attributes.zIndex = 1;
    return attributes;
}

/**
 The attributes, if any, of this section that intersect rect.

 NOTE: Does NOT include backgroundViewAttributes, since the section itself is not aware of
 the `showsSectionBackgrounds` property.
 */
- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesIntersectingRect:(CGRect)rect
{
    if (!CGRectIntersectsRect(self.frame, rect)) {
        return nil;
    }

    NSMutableArray *intersectingAttributes = [NSMutableArray new];

    UICollectionViewLayoutAttributes *headerViewAttributes = self.headerViewAttributes;
    if (headerViewAttributes && CGRectIntersectsRect(headerViewAttributes.frame, rect)) {
        [intersectingAttributes addObject:headerViewAttributes];
    }

    UICollectionViewLayoutAttributes *footerViewAttributes = self.footerViewAttributes;
    if (footerViewAttributes && CGRectIntersectsRect(footerViewAttributes.frame, rect)) {
        [intersectingAttributes addObject:footerViewAttributes];
    }

    JEKScrollableSectionDecorationViewLayoutAttributes *scrollViewAttributes = self.decorationViewAttributes;
    if (CGRectIntersectsRect(scrollViewAttributes.frame, rect)) {
        [intersectingAttributes addObject:scrollViewAttributes];
        BOOL visibleItemsFound = NO;
        for (NSInteger i = 0; i < self.numberOfItems; ++i) {
            CGRect frame = CGRectOffset(self.itemFrames[i].CGRectValue, self.offset.x, self.offset.y);
            if (CGRectIntersectsRect(frame, rect)) {
                visibleItemsFound = YES;
                [intersectingAttributes addObject:[self layoutAttributesForItemAtIndex:i]];
            }

            // Optimization: If we have seen previously intersecting items but the current one
            // doesn't intersect, we can break to avoid extra work since they are enumerated
            // in visible order.
            else if (visibleItemsFound) { break; }
        }
    }
    return intersectingAttributes;
}

- (JEKScrollableSectionDecorationView *)currentDecorationView
{
    // Make sure we can't access old references to decoration views from sections that aren't visible, since
    // they may be in the reuse queue and not in correct state
    return _currentDecorationView.superview ? _currentDecorationView : nil;
}

@end

@implementation JEKScrollViewConfiguration

+ (instancetype)defaultConfiguration
{
    return [[self alloc] init];
}

- (instancetype)init
{
    if (self = [super init]) {
        self.bounces = YES;
        self.alwaysBounceHorizontal = YES;
        self.showsHorizontalScrollIndicator = YES;
        self.scrollIndicatorInsets = UIEdgeInsetsZero;
        self.indicatorStyle = UIScrollViewIndicatorStyleDefault;
        self.decelerationRate = UIScrollViewDecelerationRateNormal;
        self.pagingEnabled = NO;
        self.scrollEnabled = YES;
    }
    return self;
}

@end

@implementation JEKScrollableSectionLayoutInvalidationContext @end


/**
 A UICollectionView-swizzle that forwards calls to scrollToItemAtIndexPath:atScrollPosition:animated:
 to the layout object. This is needed since this layout must scroll horizontal sections for these
 calls to work correctly.
 */
@interface UICollectionView (JEKScrollableSectionLayoutCollectionViewLayout) @end

@implementation UICollectionView (JEKScrollableSectionLayoutCollectionViewLayout)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod(self, @selector(scrollToItemAtIndexPath:atScrollPosition:animated:));
        Method hook = class_getInstanceMethod(self, @selector(jek_scrollToItemAtIndexPath:atScrollPosition:animated:));
        method_exchangeImplementations(original, hook);
    });
}

- (void)jek_scrollToItemAtIndexPath:(NSIndexPath *)indexPath atScrollPosition:(UICollectionViewScrollPosition)scrollPosition animated:(BOOL)animated
{
    [self jek_scrollToItemAtIndexPath:indexPath atScrollPosition:scrollPosition animated:animated];
    if ([self.collectionViewLayout isKindOfClass:JEKScrollableSectionCollectionViewLayout.class]) {
        JEKScrollableSectionCollectionViewLayout *layout = (JEKScrollableSectionCollectionViewLayout *)self.collectionViewLayout;
        [layout scrollToItemAtIndexPath:indexPath scrollPosition:scrollPosition animated:animated];
    }
}

@end
