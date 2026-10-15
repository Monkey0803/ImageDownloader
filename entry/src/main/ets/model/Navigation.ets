/**
 * 导航身份：底部页签下标与图库分段取值。
 *
 * 带名字的常量，免得页签增减时到处找裸数字；ViewModel 与组件都从这里取，不再各自抄一份。
 *
 * 下标必须与 `view/Widgets.ets` 的 `TABS` 顺序一一对应 —— 那一份是页签栏的显示顺序，
 * 这一份是内容的身份，两边只能靠约定对齐（`TabBar` 的徽标判断已经改成用 `TAB_TASKS`）。
 */
export const TAB_DISCOVER: number = 0;
export const TAB_TASKS: number = 1;
export const TAB_LIBRARY: number = 2;
export const TAB_SETTINGS: number = 3;

/**
 * 「图库」页里的两个分段。
 *
 * 这里是**唯一真源**：`view/Widgets.ets` 的 `LIBRARY_OPTIONS`（控件选项）与
 * `LibraryViewModel.segment`（状态值）都引用它 —— 两边各写一份就会出现
 * 「点得动但筛不出来」这种不报错的错。
 */
export const LIBRARY_IMAGES: string = 'images';
export const LIBRARY_ZIPS: string = 'zips';
