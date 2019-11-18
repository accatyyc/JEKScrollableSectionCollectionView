//
//  JEKScrollableSectionCollectionViewLayout.h
//  Example Project
//
//  Created by Joel Ekström on 2018-07-19.
//  Copyright © 2018 Joel Ekström. All rights reserved.
//


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class JEKScrollViewConfiguration;
@interface JEKScrollableSectionCollectionViewLayout : UICollectionViewLayout

@property (nonatomic) CGFloat minimumInteritemSpacing;
@property (nonatomic) CGSize itemSize;
@property (nonatomic) CGSize headerReferenceSize;
@property (nonatomic) CGSize footerReferenceSize;
@property (nonatomic) UIEdgeInsets sectionInset;

/**
 The scroll view settings that will be applied to each horisontal section. Can be overridden
 per section by implementing `collectionView:layout:scrollViewConfigurationForSection:`.
 */
@property (nonatomic, strong) JEKScrollViewConfiguration *defaultScrollViewConfiguration;
@property (nonatomic) BOOL showsHorizontalScrollIndicators __attribute__((deprecated("", "scrollViewConfiguration")));

/**
 When YES, collectionView:viewForSupplementaryElementOfKind:atIndexPath:
 will be queried with the kind JEKCollectionElementKindSectionBackground,
 so you can optionally return a view to be used as a background for a section.
 */
@property (nonatomic) BOOL showsSectionBackgrounds;
extern NSString * const JEKCollectionElementKindSectionBackground;

/**
 Allows you to programmatically scroll a section.
 */
- (void)setHorizontalOffset:(CGFloat)offset forSectionAtIndex:(NSUInteger)index animated:(BOOL)animated;

@end

@interface JEKScrollViewConfiguration : NSObject
+ (instancetype)defaultConfiguration;
@property (nonatomic) BOOL bounces;
@property (nonatomic) BOOL alwaysBounceHorizontal;
@property (nonatomic) BOOL showsHorizontalScrollIndicator;
@property (nonatomic) UIEdgeInsets scrollIndicatorInsets;
@property (nonatomic) UIScrollViewIndicatorStyle indicatorStyle;
@property (nonatomic) UIScrollViewDecelerationRate decelerationRate;
@property (nonatomic, getter=isPagingEnabled) BOOL pagingEnabled;
@property (nonatomic, getter=isScrollEnabled) BOOL scrollEnabled;
@end

/**
 Implement this delegate protocol to listen for scrolling events on different sections.
 The protocol closely matches UIScrollViewDelegate. Simply conform to this protocol
 instead of UICollectionViewDelegateFlowLayout and implement the required methods.
 */
@protocol JEKCollectionViewDelegateScrollableSectionLayout <UICollectionViewDelegateFlowLayout>
@optional

/**
 Optional configuration of scroll view behavior per section. Return nil to use the
 defaultScrollViewConfiguration set on the layout object.
 */
- (nullable JEKScrollViewConfiguration *)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout *)layout scrollViewConfigurationForSection:(NSUInteger)section;

/**
 Return YES to use standard flow layout for a section. The section will have multiple
 rows instead of being scrollable horizontally.
 */
- (BOOL)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout*)collectionViewLayout shouldUseFlowLayoutInSection:(NSInteger)section;

/**
 Scroll view delegate functions for horizontal sections
 */
- (void)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout *)layout section:(NSUInteger)section didScrollToOffset:(CGFloat)horizontalOffset;
- (void)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout *)layout sectionWillBeginDragging:(NSUInteger)section;
- (void)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout *)layout sectionWillEndDragging:(NSUInteger)section withVelocity:(CGFloat)velocity targetOffset:(inout CGFloat *)targetHorizontalOffset;
- (void)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout *)layout sectionDidEndDragging:(NSUInteger)section willDecelerate:(BOOL)decelerate;
- (void)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout *)layout sectionWillBeginDecelerating:(NSUInteger)section;
- (void)collectionView:(UICollectionView *)collectionView layout:(JEKScrollableSectionCollectionViewLayout *)layout sectionDidEndDecelerating:(NSUInteger)section;
@end

NS_ASSUME_NONNULL_END
