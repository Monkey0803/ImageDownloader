import { TAB_DISCOVER } from '../model/Navigation';

export interface HdsShellPlan {
  showTabs: boolean;
  titleMaterial: boolean;
  tabMaterial: boolean;
  bottomMargin: number;
}

/** Keep navigation, material and safe-area decisions in one testable place. */
export function hdsShellPlan(tab: number, browserOpen: boolean, lightEffect: boolean,
  materialType: string, immersiveSupported: boolean, indicatorHeight: number): HdsShellPlan {
  const showTabs: boolean = tab !== TAB_DISCOVER || browserOpen;
  const titleMaterial: boolean = lightEffect && materialType !== 'none' && immersiveSupported;
  const tabMaterial: boolean = titleMaterial && tab !== TAB_DISCOVER && showTabs;
  const safeHeight: number = Number.isFinite(indicatorHeight) ? Math.max(0, indicatorHeight) : 0;
  return { showTabs: showTabs, titleMaterial: titleMaterial, tabMaterial: tabMaterial,
    bottomMargin: showTabs ? Math.max(28, safeHeight) : 0 };
}
