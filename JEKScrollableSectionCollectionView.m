//
//  JEKScrollableSectionCollectionView.m
//  JEKScrollableSectionCollectionView
//
//  Created by Joel Ekström on 2017-08-28.
//  Copyright © 2017 Joel Ekström. All rights reserved.
//

#import "JEKScrollableSectionCollectionView.h"

@class JEKScrollableCollectionViewController;
@class JEKCollectionViewWrapperCell;

@interface JEKScrollableSectionCollectionView()

@property (nonatomic, strong) JEKScrollableCollectionViewController *controller;
@property (nonatomic, strong) NSMutableDictionary<NSString *, Class> *registeredCellClasses;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UINib *> *registeredCellNibs;
@property (nonatomic, assign) NSUInteger registrationHash;

@property (nonatomic, strong) NSIndexPath *queuedIndexPath;
@property (nonatomic, assign) BOOL shouldAnimateScrollToQueuedIndexPath;

@end

@interface JEKScrollableCollectionViewController : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching>

@property (nonatomic, weak) JEKScrollableSectionCollectionView *collectionView;
@property (nonatomic, weak) id<UICollectionViewDataSource> externalDataSource;
@property (nonatomic, weak) id<UICollectionViewDelegateFlowLayout> externalDelegate;
@property (nonatomic, weak) id<UICollectionViewDataSourcePrefetching> externalPrefetchingDataSource;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *selectedIndexPaths;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *contentOffsetCache;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, JEKCollectionViewWrapperCell *> *visibleCells;

- (instancetype)initWithCollectionView:(JEKScrollableSectionCollectionView *)collectionView;

@end

static NSString * const JEKCollectionViewWrapperCellIdentifier = @"JEKCollectionViewWrapperCellIdentifier";

@interface JEKCollectionViewWrapperCell : UICollectionViewCell

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, assign) NSUInteger registrationHash;

- (void)registerCellClasses:(NSDictionary<NSString *, Class> *)classes nibs:(NSDictionary<NSString *, UINib *> *)nibs;

@end

#pragma mark -

@implementation JEKScrollableSectionCollectionView

- (instancetype)initWithFrame:(CGRect)frame collectionViewLayout:(UICollectionViewFlowLayout *)layout
{
    NSAssert([layout isKindOfClass:UICollectionViewFlowLayout.class], @"%@ must be initialized with a UICollectionViewFlowLayout", NSStringFromClass(self.class));
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    if (self = [super initWithFrame:frame collectionViewLayout:layout]) {
        self.controller = [[JEKScrollableCollectionViewController alloc] initWithCollectionView:self];
        self.registeredCellClasses = [NSMutableDictionary new];
        self.registeredCellNibs = [NSMutableDictionary new];
        [super registerClass:JEKCollectionViewWrapperCell.class forCellWithReuseIdentifier:JEKCollectionViewWrapperCellIdentifier];
    }
    return self;
}

- (void)setDelegate:(id<UICollectionViewDelegate>)delegate
{
    [super setDelegate:delegate ? self.controller : nil];
    self.controller.externalDelegate = (id<UICollectionViewDelegateFlowLayout>)delegate;
}

- (void)setDataSource:(id<UICollectionViewDataSource>)dataSource
{
    [super setDataSource:dataSource ? self.controller : nil];
    self.controller.externalDataSource = dataSource;
}

- (void)setPrefetchDataSource:(id<UICollectionViewDataSourcePrefetching>)prefetchDataSource
{
    self.controller.externalPrefetchingDataSource = prefetchDataSource;
}

- (void)registerClass:(Class)cellClass forCellWithReuseIdentifier:(NSString *)identifier
{
    _registeredCellClasses[identifier] = cellClass;
    [self updateRegistrationHash];
}

- (void)registerNib:(UINib *)nib forCellWithReuseIdentifier:(NSString *)identifier
{
    _registeredCellNibs[identifier] = nib;
    [self updateRegistrationHash];
}

- (void)updateRegistrationHash
{
    self.registrationHash = [self.registeredCellClasses.description hash] ^ [self.registeredCellNibs.description hash];
}

- (__kindof UICollectionViewCell *)dequeueReusableCellWithReuseIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath
{
    if ([identifier isEqualToString:JEKCollectionViewWrapperCellIdentifier]) {
        return [super dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    }

    JEKCollectionViewWrapperCell *cell = self.controller.visibleCells[@(indexPath.section)];
    return [cell.collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:0]];
}

- (UICollectionViewCell *)cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    JEKCollectionViewWrapperCell *wrapperCell = self.controller.visibleCells[@(indexPath.section)];
    return [wrapperCell.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:0]];
}

- (NSArray<NSIndexPath *> *)indexPathsForSelectedItems
{
    return self.controller.selectedIndexPaths.allObjects;
}

- (NSArray<__kindof UICollectionViewCell *> *)visibleCells
{
    NSArray *visibleCells = @[];
    for (JEKCollectionViewWrapperCell *cell in self.controller.visibleCells) {
        visibleCells = [visibleCells arrayByAddingObjectsFromArray:cell.collectionView.visibleCells];
    }
    return visibleCells;
}

- (NSArray<NSIndexPath *> *)indexPathsForVisibleItems
{
    NSArray *visibleIndexPaths = @[];
    for (UICollectionViewCell *cell in self.controller.visibleCells) {
        visibleIndexPaths = [visibleIndexPaths arrayByAddingObject:[self indexPathForCell:cell]];
    }
    return visibleIndexPaths;
}

- (NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell
{
    if ([cell.superview.superview isKindOfClass:JEKCollectionViewWrapperCell.class]) {
        JEKCollectionViewWrapperCell *wrapperCell = (JEKCollectionViewWrapperCell *)cell.superview.superview;
        NSIndexPath *indexPath = [wrapperCell.collectionView indexPathForCell:cell];
        return [NSIndexPath indexPathForItem:indexPath.item inSection:wrapperCell.collectionView.tag];
    }
    return nil;
}

- (void)scrollToItemAtIndexPath:(NSIndexPath *)indexPath atScrollPosition:(UICollectionViewScrollPosition)scrollPosition animated:(BOOL)animated
{
    NSIndexPath *outerIndexPath = [NSIndexPath indexPathForItem:0 inSection:indexPath.section];
    NSIndexPath *innerIndexPath = [NSIndexPath indexPathForItem:indexPath.item inSection:0];
    [super scrollToItemAtIndexPath:outerIndexPath atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:animated];
    JEKCollectionViewWrapperCell *cell = self.controller.visibleCells[@(indexPath.section)];
    if (cell) {
        [cell.collectionView scrollToItemAtIndexPath:innerIndexPath atScrollPosition:scrollPosition animated:animated];
    } else {
        self.queuedIndexPath = indexPath;
        self.shouldAnimateScrollToQueuedIndexPath = animated;
    }
}

- (void)selectItemAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated scrollPosition:(UICollectionViewScrollPosition)scrollPosition
{
    [self.controller.selectedIndexPaths addObject:indexPath];
    JEKCollectionViewWrapperCell *wrapperCell = self.controller.visibleCells[@(indexPath.section)];
    [wrapperCell.collectionView selectItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:0] animated:animated scrollPosition:scrollPosition];

    if (scrollPosition != UICollectionViewScrollPositionNone) {
        [self scrollToItemAtIndexPath:indexPath atScrollPosition:scrollPosition animated:animated];
    }
}

- (void)deselectItemAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated
{
    [self.controller.selectedIndexPaths removeObject:indexPath];
    JEKCollectionViewWrapperCell *wrapperCell = self.controller.visibleCells[@(indexPath.section)];
    [wrapperCell.collectionView deselectItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:0] animated:animated];
}

#pragma mark -

- (CGPoint)contentOffsetForSection:(NSInteger)section
{
    JEKCollectionViewWrapperCell *cell = self.controller.visibleCells[@(section)];
    if (cell) {
        return cell.collectionView.contentOffset;
    } else {
        return CGPointZero;
    }
}

- (void)setContentOffset:(CGPoint)contentOffset forSection:(NSInteger)section
{
    JEKCollectionViewWrapperCell *cell = self.controller.visibleCells[@(section)];
    if (cell) {
        cell.collectionView.contentOffset = contentOffset;
    }
}

#pragma mark Updating content

- (void)insertItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self performSelector:_cmd forItemsAtIndexPaths:indexPaths];
}

- (void)deleteItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self performSelector:_cmd forItemsAtIndexPaths:indexPaths];
}

- (void)reloadItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [self performSelector:_cmd forItemsAtIndexPaths:indexPaths];
}

- (void)moveItemAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath
{
    JEKCollectionViewWrapperCell *cell = self.controller.visibleCells[@(indexPath.section)];
    if (indexPath.section == newIndexPath.section) {
        // When moving within a single section, we can just forward the move to the child collection view
        [cell.collectionView moveItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:0] toIndexPath:[NSIndexPath indexPathForItem:newIndexPath.item inSection:0]];
    } else {
        // Otherwise, we use delete/insert instead in the respective cells
        JEKCollectionViewWrapperCell *cell2 = self.controller.visibleCells[@(indexPath.section)];
        [cell.collectionView deleteItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:indexPath.item inSection:0]]];
        [cell2.collectionView insertItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:newIndexPath.item inSection:0]]];
    }
}

/**
 When performing batch updates, we need all child collection views to be in batch update mode.
 This function recursively begins performing batch updates on an array of cells, and runs the
 update block in the last one
 */
- (void)performBatchUpdatesInLastCell:(NSArray<JEKCollectionViewWrapperCell *> *)cells updates:(void (^)(void))updates
{
    if (cells.count > 0) {
        [cells.firstObject.collectionView performBatchUpdates:^{
            [self performBatchUpdatesInLastCell:[cells subarrayWithRange:NSMakeRange(1, cells.count - 1)] updates:updates];
        } completion:nil];
    } else {
        updates();
    }
}

- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL))completion
{
    [super performBatchUpdates:^{
        [self performBatchUpdatesInLastCell:self.controller.visibleCells.allValues updates:updates];
    } completion:completion];
}

/**
 When inserting/deleting/reloading items, we want to do it in the relevant child collection views.
 This method finds the relevat collection views and transforms the index paths for them.
 */
- (void)performSelector:(SEL)selector forItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    [[self indexPathsGroupedBySection:indexPaths] enumerateKeysAndObjectsUsingBlock:^(NSNumber *section, NSArray<NSIndexPath *> *indexPaths, BOOL *stop) {
        JEKCollectionViewWrapperCell *cell = self.controller.visibleCells[section];
        if ([cell.collectionView respondsToSelector:selector]) {
            IMP imp = [cell.collectionView methodForSelector:selector];
            void (*functionPtr)(id, SEL, NSArray<NSIndexPath *> *) = (void *)imp;
            functionPtr(cell.collectionView, selector, indexPaths);
        }
    }];
}

/**
 Transforms an array of indexPaths into a dictionary grouped by section where each key is the
 section index. The actual section is removed from the indexPath objects and replaced by 0.
 */
- (NSDictionary<NSNumber *, NSArray<NSIndexPath *> *> *)indexPathsGroupedBySection:(NSArray<NSIndexPath *> *)indexPaths
{
    NSMutableDictionary *groupedIndexPaths = [NSMutableDictionary new];
    indexPaths = [indexPaths sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"section" ascending:YES]]];

    NSMutableArray<NSIndexPath *> *currentSectionArray = nil;
    NSInteger currentSectionIndex = -1;
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.section != currentSectionIndex) {
            currentSectionIndex = indexPath.section;
            currentSectionArray = [NSMutableArray new];
            groupedIndexPaths[@(currentSectionIndex)] = currentSectionArray;
        }
        [currentSectionArray addObject:[NSIndexPath indexPathForItem:indexPath.item inSection:0]];
    }

    return [groupedIndexPaths copy];
}

@end

#pragma mark -

@implementation JEKScrollableCollectionViewController

- (instancetype)initWithCollectionView:(JEKScrollableSectionCollectionView *)collectionView
{
    if (self = [super init]) {
        self.collectionView = collectionView;
        self.selectedIndexPaths = [NSMutableSet new];
        self.contentOffsetCache = [NSMutableDictionary new];
        self.visibleCells = [NSMutableDictionary new];
    }
    return self;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    if (collectionView == self.collectionView) {
        return [self.externalDataSource numberOfSectionsInCollectionView:collectionView];
    }
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (collectionView == self.collectionView) {
        return 1;
    }
    return [self.externalDataSource collectionView:self.collectionView numberOfItemsInSection:collectionView.tag];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    if (collectionView == self.collectionView) {
        JEKCollectionViewWrapperCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:JEKCollectionViewWrapperCellIdentifier forIndexPath:indexPath];
        cell.collectionView.tag = indexPath.section;
        if (cell.registrationHash != self.collectionView.registrationHash) {
            [cell registerCellClasses:self.collectionView.registeredCellClasses nibs:self.collectionView.registeredCellNibs];
            cell.registrationHash = self.collectionView.registrationHash;
        }
        return cell;
    }
    return [self.externalDataSource collectionView:self.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag]];
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if (collectionView == self.collectionView && [self.externalDataSource respondsToSelector:_cmd]) {
        return [self.externalDataSource collectionView:collectionView viewForSupplementaryElementOfKind:kind atIndexPath:indexPath];
    }
    return nil;
}

#pragma mark UICollectionViewDataSourcePrefetching

- (void)collectionView:(UICollectionView *)collectionView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    if ([self.externalPrefetchingDataSource respondsToSelector:_cmd]) {
        NSMutableArray *transformedIndexPaths = [NSMutableArray new];
        for (NSIndexPath *indexPath in indexPaths) {
            [transformedIndexPaths addObject:[NSIndexPath indexPathForItem:indexPath.section inSection:collectionView.tag]];
        }
        [self.externalPrefetchingDataSource collectionView:self.collectionView prefetchItemsAtIndexPaths:[transformedIndexPaths copy]];
    }
}

- (void)collectionView:(UICollectionView *)collectionView cancelPrefetchingForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
    if ([self.externalPrefetchingDataSource respondsToSelector:_cmd]) {
        NSMutableArray *transformedIndexPaths = [NSMutableArray new];
        for (NSIndexPath *indexPath in indexPaths) {
            [transformedIndexPaths addObject:[NSIndexPath indexPathForItem:indexPath.section inSection:collectionView.tag]];
        }
        [self.externalPrefetchingDataSource collectionView:self.collectionView cancelPrefetchingForItemsAtIndexPaths:[transformedIndexPaths copy]];
    }
}

#pragma mark UICollectionViewDelegate

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (collectionView == self.collectionView) {
        UICollectionViewFlowLayout *flowLayout = (UICollectionViewFlowLayout *)collectionViewLayout;
        CGSize size = CGSizeMake(CGRectGetWidth(collectionView.frame), flowLayout.itemSize.height);
        if ([self.externalDelegate respondsToSelector:@selector(collectionView:heightForSectionAtIndex:)]) {
            size.height = [(id)self.externalDelegate collectionView:self.collectionView heightForSectionAtIndex:indexPath.section];
        }
        return size;
    }

    if ([self.externalDelegate respondsToSelector:_cmd]) {
        return [self.externalDelegate collectionView:self.collectionView
                                              layout:self.collectionView.collectionViewLayout
                              sizeForItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag]];
    }

    return [(UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout itemSize];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section
{
    if (collectionView == self.collectionView) {
        if ([self.externalDelegate respondsToSelector:_cmd]) {
            return [self.externalDelegate collectionView:self.collectionView layout:collectionViewLayout referenceSizeForHeaderInSection:section];
        }
        return collectionViewLayout.headerReferenceSize;
    }
    return CGSizeZero;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout referenceSizeForFooterInSection:(NSInteger)section
{
    if (collectionView == self.collectionView) {
        if ([self.externalDelegate respondsToSelector:_cmd]) {
            return [self.externalDelegate collectionView:self.collectionView layout:collectionViewLayout referenceSizeForFooterInSection:section];
        }
        return collectionViewLayout.footerReferenceSize;
    }
    return CGSizeZero;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    if (collectionView == self.collectionView) {
        return 0.0;
    }

    // Call the inter-item spacing function of the delegate instead, since that's what you expect from a vertical collection view.
    // The inner collection views are actually horizontal, but that's unknown outside this class
    if ([self.externalDelegate respondsToSelector:@selector(collectionView:layout:minimumInteritemSpacingForSectionAtIndex:)]) {
        return [self.externalDelegate collectionView:self.collectionView layout:self.collectionView.collectionViewLayout minimumInteritemSpacingForSectionAtIndex:collectionView.tag];
    }

    return [(UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout minimumInteritemSpacing];
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section
{
    if (collectionView == self.collectionView) {
        return 0.0;
    }

    // Use minimumLineSpacing instead. See comment in minimumLineSpacing for more info
    if ([self.externalDelegate respondsToSelector:@selector(collectionView:layout:minimumLineSpacingForSectionAtIndex:)]) {
        return [self.externalDelegate collectionView:self.collectionView layout:self.collectionView.collectionViewLayout minimumLineSpacingForSectionAtIndex:collectionView.tag];
    }

    return [(UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout minimumLineSpacing];
}


- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewFlowLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section
{
    if (collectionView == self.collectionView) {
        return UIEdgeInsetsZero;
    }

    if ([self.externalDelegate respondsToSelector:_cmd]) {
        return [self.externalDelegate collectionView:collectionView layout:self.collectionView.collectionViewLayout insetForSectionAtIndex:collectionView.tag];
    }

    return [(UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout sectionInset];
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (collectionView == self.collectionView) {
        JEKCollectionViewWrapperCell *wrapperCell = (JEKCollectionViewWrapperCell *)cell;
        wrapperCell.collectionView.dataSource = self;
        wrapperCell.collectionView.delegate = self;
        wrapperCell.collectionView.prefetchDataSource = _externalPrefetchingDataSource ? self : nil;
        wrapperCell.collectionView.allowsMultipleSelection = collectionView.allowsMultipleSelection;
        wrapperCell.collectionView.allowsSelection = collectionView.allowsSelection;
        wrapperCell.collectionView.showsHorizontalScrollIndicator = self.collectionView.showsHorizontalScrollIndicator;
        self.visibleCells[@(indexPath.section)] = wrapperCell;
        [wrapperCell.collectionView reloadData];

        NSValue *contentOffset = self.contentOffsetCache[@(indexPath.section)];
        wrapperCell.collectionView.contentOffset = contentOffset ? contentOffset.CGPointValue : CGPointZero;

        for (NSIndexPath *indexPath in self.selectedIndexPaths) {
            if (indexPath.section == wrapperCell.collectionView.tag) {
                [wrapperCell.collectionView selectItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:0] animated:NO scrollPosition:UICollectionViewScrollPositionNone];
            }
        }

        if (self.collectionView.queuedIndexPath && self.collectionView.queuedIndexPath.section == wrapperCell.collectionView.tag) {
            [wrapperCell.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.collectionView.queuedIndexPath.item inSection:0]
                                               atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally
                                                       animated:self.collectionView.shouldAnimateScrollToQueuedIndexPath];
            self.collectionView.queuedIndexPath = nil;
        }
    } else if ([self.externalDelegate respondsToSelector:_cmd]) {
        [self.externalDelegate collectionView:self.collectionView willDisplayCell:cell forItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag]];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (collectionView == self.collectionView) {
        JEKCollectionViewWrapperCell *wrapperCell = (JEKCollectionViewWrapperCell *)cell;
        NSNumber *section = @(indexPath.section);
        self.contentOffsetCache[section] = [NSValue valueWithCGPoint:wrapperCell.collectionView.contentOffset];
        wrapperCell.collectionView.dataSource = nil;
        wrapperCell.collectionView.delegate = nil;
        wrapperCell.collectionView.prefetchDataSource = nil;

        for (NSIndexPath *indexPath in wrapperCell.collectionView.indexPathsForSelectedItems) {
            [wrapperCell.collectionView deselectItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:0] animated:NO];
        }

        if (self.visibleCells[section] == wrapperCell) {
            self.visibleCells[section] = nil;
        }
    } else if ([self.externalDelegate respondsToSelector:_cmd]) {
        [self.externalDelegate collectionView:self.collectionView didEndDisplayingCell:cell forItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag]];
    }
}

- (void)collectionView:(UICollectionView *)collectionView willDisplaySupplementaryView:(nonnull UICollectionReusableView *)view forElementKind:(nonnull NSString *)elementKind atIndexPath:(nonnull NSIndexPath *)indexPath
{
    if ([self.externalDelegate respondsToSelector:_cmd]) {
        [self.externalDelegate collectionView:collectionView willDisplaySupplementaryView:view forElementKind:elementKind atIndexPath:indexPath];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingSupplementaryView:(UICollectionReusableView *)view forElementOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    if ([self.externalDelegate respondsToSelector:_cmd]) {
        [self.externalDelegate collectionView:collectionView didEndDisplayingSupplementaryView:view forElementOfKind:elementKind atIndexPath:indexPath];
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (collectionView == self.collectionView) {
        return NO;
    } else if ([self.externalDelegate respondsToSelector:_cmd]) {
        return [self.externalDelegate collectionView:self.collectionView shouldHighlightItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag]];
    }
    return YES;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (collectionView == self.collectionView) {
        return NO;
    } else if ([self.externalDelegate respondsToSelector:_cmd]) {
        return [self.externalDelegate collectionView:self.collectionView shouldSelectItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag]];
    }
    return YES;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.externalDelegate respondsToSelector:_cmd]) {
        return [self.externalDelegate collectionView:self.collectionView shouldDeselectItemAtIndexPath:[NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag]];
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath *externalIndexPath = [NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag];
    NSIndexPath *previousSelection = [self.selectedIndexPaths anyObject];

    if (!self.collectionView.allowsMultipleSelection && previousSelection && ![previousSelection isEqual:externalIndexPath]) {
        [self.collectionView deselectItemAtIndexPath:previousSelection animated:NO];
    }

    [self.selectedIndexPaths addObject:externalIndexPath];

    if ([self.externalDelegate respondsToSelector:_cmd]) {
        [self.externalDelegate collectionView:self.collectionView didSelectItemAtIndexPath:externalIndexPath];
    }
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    NSIndexPath *externalIndexPath = [NSIndexPath indexPathForItem:indexPath.item inSection:collectionView.tag];
    [self.selectedIndexPaths removeObject:externalIndexPath];
    if ([self.externalDelegate respondsToSelector:_cmd]) {
        [self.externalDelegate collectionView:self.collectionView didDeselectItemAtIndexPath:externalIndexPath];
    }
}

@end

#pragma mark -

@implementation JEKCollectionViewWrapperCell

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
        layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        self.collectionView = [[UICollectionView alloc] initWithFrame:self.contentView.bounds collectionViewLayout:layout];
        self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.collectionView.alwaysBounceHorizontal = YES;
        self.collectionView.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.collectionView];
    }
    return self;
}

- (void)registerCellClasses:(NSDictionary<NSString *, Class> *)classes nibs:(NSDictionary<NSString *, UINib *> *)nibs
{
    [classes enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, Class class, BOOL * _Nonnull stop) {
        [self.collectionView registerClass:class forCellWithReuseIdentifier:identifier];
    }];

    [nibs enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, UINib *nib, BOOL * _Nonnull stop) {
        [self.collectionView registerNib:nib forCellWithReuseIdentifier:identifier];
    }];
}

@end
