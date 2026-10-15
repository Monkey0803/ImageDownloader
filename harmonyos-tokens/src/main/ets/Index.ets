/*
 * Theme.ets — GENERATED FILE. Do not edit.
 *
 * Source of truth: designs/harmonyos-mobile/tokens/*.css
 * Regenerate:      node tools/build-token-har.mjs
 *
 * Colours are Resource references so the platform swaps in resources/dark at
 * runtime. Dimensions are plain numbers so a screen can compose them (this system's
 * bottom geometry depends on the live safe-area insets, which needs arithmetic).
 *
 * NOTE — an app CANNOT override these values by redeclaring the same resource name.
 * Verified by building a conflicting declaration: the toolchain prints
 *   "Warning: 'hm_brand' conflict, first declared."
 * and the HAR's value wins; the app's is dropped. So a resource name is owned by
 * whichever module declares it first, and this HAR is first.
 */

/** Theme-aware colours. The light/dark values live in resources/{base,dark}. */
export class Palette {
  /** `$r('app.color.hm_alert')` */
  static readonly alert: Resource = $r('app.color.hm_alert');
  /** `$r('app.color.hm_background_emphasize')` */
  static readonly backgroundEmphasize: Resource = $r('app.color.hm_background_emphasize');
  /** `$r('app.color.hm_background_fourth')` */
  static readonly backgroundFourth: Resource = $r('app.color.hm_background_fourth');
  /** `$r('app.color.hm_background_primary')` */
  static readonly backgroundPrimary: Resource = $r('app.color.hm_background_primary');
  /** `$r('app.color.hm_background_secondary')` */
  static readonly backgroundSecondary: Resource = $r('app.color.hm_background_secondary');
  /** `$r('app.color.hm_background_tertiary')` */
  static readonly backgroundTertiary: Resource = $r('app.color.hm_background_tertiary');
  /** `$r('app.color.hm_bg_elevated')` */
  static readonly bgElevated: Resource = $r('app.color.hm_bg_elevated');
  /** `$r('app.color.hm_bg_surface')` */
  static readonly bgSurface: Resource = $r('app.color.hm_bg_surface');
  /** `$r('app.color.hm_border')` */
  static readonly border: Resource = $r('app.color.hm_border');
  /** `$r('app.color.hm_brand')` */
  static readonly brand: Resource = $r('app.color.hm_brand');
  /** `$r('app.color.hm_brand_color')` */
  static readonly brandColor: Resource = $r('app.color.hm_brand_color');
  /** `$r('app.color.hm_brand_text')` */
  static readonly brandText: Resource = $r('app.color.hm_brand_text');
  /** `$r('app.color.hm_comp_background_emphasize')` */
  static readonly compBackgroundEmphasize: Resource = $r('app.color.hm_comp_background_emphasize');
  /** `$r('app.color.hm_comp_background_focus')` */
  static readonly compBackgroundFocus: Resource = $r('app.color.hm_comp_background_focus');
  /** `$r('app.color.hm_comp_background_gray')` */
  static readonly compBackgroundGray: Resource = $r('app.color.hm_comp_background_gray');
  /** `$r('app.color.hm_comp_background_neutral')` */
  static readonly compBackgroundNeutral: Resource = $r('app.color.hm_comp_background_neutral');
  /** `$r('app.color.hm_comp_background_primary')` */
  static readonly compBackgroundPrimary: Resource = $r('app.color.hm_comp_background_primary');
  /** `$r('app.color.hm_comp_background_primary_contrary')` */
  static readonly compBackgroundPrimaryContrary: Resource = $r('app.color.hm_comp_background_primary_contrary');
  /** `$r('app.color.hm_comp_background_secondary')` */
  static readonly compBackgroundSecondary: Resource = $r('app.color.hm_comp_background_secondary');
  /** `$r('app.color.hm_comp_background_tertiary')` */
  static readonly compBackgroundTertiary: Resource = $r('app.color.hm_comp_background_tertiary');
  /** `$r('app.color.hm_comp_common_contrary')` */
  static readonly compCommonContrary: Resource = $r('app.color.hm_comp_common_contrary');
  /** `$r('app.color.hm_comp_divider')` */
  static readonly compDivider: Resource = $r('app.color.hm_comp_divider');
  /** `$r('app.color.hm_comp_emphasize_secondary')` */
  static readonly compEmphasizeSecondary: Resource = $r('app.color.hm_comp_emphasize_secondary');
  /** `$r('app.color.hm_comp_emphasize_tertiary')` */
  static readonly compEmphasizeTertiary: Resource = $r('app.color.hm_comp_emphasize_tertiary');
  /** `$r('app.color.hm_comp_focused_primary')` */
  static readonly compFocusedPrimary: Resource = $r('app.color.hm_comp_focused_primary');
  /** `$r('app.color.hm_comp_focused_secondary')` */
  static readonly compFocusedSecondary: Resource = $r('app.color.hm_comp_focused_secondary');
  /** `$r('app.color.hm_comp_focused_tertiary')` */
  static readonly compFocusedTertiary: Resource = $r('app.color.hm_comp_focused_tertiary');
  /** `$r('app.color.hm_comp_foreground_primary')` */
  static readonly compForegroundPrimary: Resource = $r('app.color.hm_comp_foreground_primary');
  /** `$r('app.color.hm_confirm')` */
  static readonly confirm: Resource = $r('app.color.hm_confirm');
  /** `$r('app.color.hm_divider_color')` */
  static readonly dividerColor: Resource = $r('app.color.hm_divider_color');
  /** `$r('app.color.hm_font_emphasize')` */
  static readonly fontEmphasize: Resource = $r('app.color.hm_font_emphasize');
  /** `$r('app.color.hm_font_fourth')` */
  static readonly fontFourth: Resource = $r('app.color.hm_font_fourth');
  /** `$r('app.color.hm_font_on_fourth')` */
  static readonly fontOnFourth: Resource = $r('app.color.hm_font_on_fourth');
  /** `$r('app.color.hm_font_on_primary')` */
  static readonly fontOnPrimary: Resource = $r('app.color.hm_font_on_primary');
  /** `$r('app.color.hm_font_on_secondary')` */
  static readonly fontOnSecondary: Resource = $r('app.color.hm_font_on_secondary');
  /** `$r('app.color.hm_font_on_tertiary')` */
  static readonly fontOnTertiary: Resource = $r('app.color.hm_font_on_tertiary');
  /** `$r('app.color.hm_font_primary')` */
  static readonly fontPrimary: Resource = $r('app.color.hm_font_primary');
  /** `$r('app.color.hm_font_secondary')` */
  static readonly fontSecondary: Resource = $r('app.color.hm_font_secondary');
  /** `$r('app.color.hm_font_tertiary')` */
  static readonly fontTertiary: Resource = $r('app.color.hm_font_tertiary');
  /** `$r('app.color.hm_icon_btn_bg')` */
  static readonly iconBtnBg: Resource = $r('app.color.hm_icon_btn_bg');
  /** `$r('app.color.hm_icon_emphasize')` */
  static readonly iconEmphasize: Resource = $r('app.color.hm_icon_emphasize');
  /** `$r('app.color.hm_icon_fourth')` */
  static readonly iconFourth: Resource = $r('app.color.hm_icon_fourth');
  /** `$r('app.color.hm_icon_on_fourth')` */
  static readonly iconOnFourth: Resource = $r('app.color.hm_icon_on_fourth');
  /** `$r('app.color.hm_icon_on_primary')` */
  static readonly iconOnPrimary: Resource = $r('app.color.hm_icon_on_primary');
  /** `$r('app.color.hm_icon_on_secondary')` */
  static readonly iconOnSecondary: Resource = $r('app.color.hm_icon_on_secondary');
  /** `$r('app.color.hm_icon_on_tertiary')` */
  static readonly iconOnTertiary: Resource = $r('app.color.hm_icon_on_tertiary');
  /** `$r('app.color.hm_icon_primary')` */
  static readonly iconPrimary: Resource = $r('app.color.hm_icon_primary');
  /** `$r('app.color.hm_icon_secondary')` */
  static readonly iconSecondary: Resource = $r('app.color.hm_icon_secondary');
  /** `$r('app.color.hm_icon_sub_emphasize')` */
  static readonly iconSubEmphasize: Resource = $r('app.color.hm_icon_sub_emphasize');
  /** `$r('app.color.hm_icon_tertiary')` */
  static readonly iconTertiary: Resource = $r('app.color.hm_icon_tertiary');
  /** `$r('app.color.hm_interactive_active')` */
  static readonly interactiveActive: Resource = $r('app.color.hm_interactive_active');
  /** `$r('app.color.hm_interactive_click')` */
  static readonly interactiveClick: Resource = $r('app.color.hm_interactive_click');
  /** `$r('app.color.hm_interactive_focus')` */
  static readonly interactiveFocus: Resource = $r('app.color.hm_interactive_focus');
  /** `$r('app.color.hm_interactive_hover')` */
  static readonly interactiveHover: Resource = $r('app.color.hm_interactive_hover');
  /** `$r('app.color.hm_interactive_pressed')` */
  static readonly interactivePressed: Resource = $r('app.color.hm_interactive_pressed');
  /** `$r('app.color.hm_interactive_select')` */
  static readonly interactiveSelect: Resource = $r('app.color.hm_interactive_select');
  /** `$r('app.color.hm_overlay_bg')` */
  static readonly overlayBg: Resource = $r('app.color.hm_overlay_bg');
  /** `$r('app.color.hm_text_fourth')` */
  static readonly textFourth: Resource = $r('app.color.hm_text_fourth');
  /** `$r('app.color.hm_text_primary')` */
  static readonly textPrimary: Resource = $r('app.color.hm_text_primary');
  /** `$r('app.color.hm_text_secondary')` */
  static readonly textSecondary: Resource = $r('app.color.hm_text_secondary');
  /** `$r('app.color.hm_text_tertiary')` */
  static readonly textTertiary: Resource = $r('app.color.hm_text_tertiary');
  /** `$r('app.color.hm_warning')` */
  static readonly warning: Resource = $r('app.color.hm_warning');
  /** `$r('app.color.hm_x_legacy_brand_008')` */
  static readonly xLegacyBrand008: Resource = $r('app.color.hm_x_legacy_brand_008');
  /** `$r('app.color.hm_x_legacy_brand_035')` */
  static readonly xLegacyBrand035: Resource = $r('app.color.hm_x_legacy_brand_035');
  /** `$r('app.color.hm_x_legacy_brand_075')` */
  static readonly xLegacyBrand075: Resource = $r('app.color.hm_x_legacy_brand_075');
  /** `$r('app.color.hm_x_legacy_brand_old')` */
  static readonly xLegacyBrandOld: Resource = $r('app.color.hm_x_legacy_brand_old');
  /** `$r('app.color.hm_x_legacy_cyan_accent')` */
  static readonly xLegacyCyanAccent: Resource = $r('app.color.hm_x_legacy_cyan_accent');
  /** `$r('app.color.hm_x_legacy_frosted_surface')` */
  static readonly xLegacyFrostedSurface: Resource = $r('app.color.hm_x_legacy_frosted_surface');
  /** `$r('app.color.hm_x_legacy_meta_text')` */
  static readonly xLegacyMetaText: Resource = $r('app.color.hm_x_legacy_meta_text');
  /** `$r('app.color.hm_x_legacy_orange_bg')` */
  static readonly xLegacyOrangeBg: Resource = $r('app.color.hm_x_legacy_orange_bg');
  /** `$r('app.color.hm_x_legacy_orange_solid')` */
  static readonly xLegacyOrangeSolid: Resource = $r('app.color.hm_x_legacy_orange_solid');
  /** `$r('app.color.hm_x_legacy_orange_text')` */
  static readonly xLegacyOrangeText: Resource = $r('app.color.hm_x_legacy_orange_text');
  /** `$r('app.color.hm_x_legacy_overlay_004')` */
  static readonly xLegacyOverlay004: Resource = $r('app.color.hm_x_legacy_overlay_004');
  /** `$r('app.color.hm_x_legacy_overlay_005')` */
  static readonly xLegacyOverlay005: Resource = $r('app.color.hm_x_legacy_overlay_005');
  /** `$r('app.color.hm_x_legacy_overlay_006')` */
  static readonly xLegacyOverlay006: Resource = $r('app.color.hm_x_legacy_overlay_006');
  /** `$r('app.color.hm_x_legacy_overlay_008')` */
  static readonly xLegacyOverlay008: Resource = $r('app.color.hm_x_legacy_overlay_008');
  /** `$r('app.color.hm_x_legacy_overlay_010')` */
  static readonly xLegacyOverlay010: Resource = $r('app.color.hm_x_legacy_overlay_010');
  /** `$r('app.color.hm_x_legacy_overlay_012')` */
  static readonly xLegacyOverlay012: Resource = $r('app.color.hm_x_legacy_overlay_012');
  /** `$r('app.color.hm_x_legacy_overlay_016')` */
  static readonly xLegacyOverlay016: Resource = $r('app.color.hm_x_legacy_overlay_016');
  /** `$r('app.color.hm_x_legacy_overlay_020')` */
  static readonly xLegacyOverlay020: Resource = $r('app.color.hm_x_legacy_overlay_020');
  /** `$r('app.color.hm_x_legacy_page_bg')` */
  static readonly xLegacyPageBg: Resource = $r('app.color.hm_x_legacy_page_bg');
  /** `$r('app.color.hm_x_legacy_panel_border')` */
  static readonly xLegacyPanelBorder: Resource = $r('app.color.hm_x_legacy_panel_border');
  /** `$r('app.color.hm_x_legacy_stroke_mid')` */
  static readonly xLegacyStrokeMid: Resource = $r('app.color.hm_x_legacy_stroke_mid');
  /** `$r('app.color.hm_x_legacy_title_text')` */
  static readonly xLegacyTitleText: Resource = $r('app.color.hm_x_legacy_title_text');
  /** `$r('app.color.hm_x_legacy_white_085')` */
  static readonly xLegacyWhite085: Resource = $r('app.color.hm_x_legacy_white_085');
}

/** Dimensions and type sizes, in vp (fp for the font sizes). Plain numbers so a
 *  screen can compose them — see the note in the generator. */
export class Metrics {
  /** 12vp — `$r('app.float.hm_card_gap_mobile')` */
  static readonly cardGapMobile: number = 12;
  /** 328vp — `$r('app.float.hm_content_width')` */
  static readonly contentWidth: number = 328;
  /** 28vp — `$r('app.float.hm_control_height_28')` */
  static readonly controlHeight28: number = 28;
  /** 36vp — `$r('app.float.hm_control_height_36')` */
  static readonly controlHeight36: number = 36;
  /** 40vp — `$r('app.float.hm_control_height_40')` */
  static readonly controlHeight40: number = 40;
  /** 56vp — `$r('app.float.hm_control_height_56')` */
  static readonly controlHeight56: number = 56;
  /** 64vp — `$r('app.float.hm_control_height_64')` */
  static readonly controlHeight64: number = 64;
  /** 72vp — `$r('app.float.hm_control_height_72')` */
  static readonly controlHeight72: number = 72;
  /** 2vp — `$r('app.float.hm_corner_radius_level1')` */
  static readonly cornerRadiusLevel1: number = 2;
  /** 20vp — `$r('app.float.hm_corner_radius_level10')` */
  static readonly cornerRadiusLevel10: number = 20;
  /** 22vp — `$r('app.float.hm_corner_radius_level11')` */
  static readonly cornerRadiusLevel11: number = 22;
  /** 24vp — `$r('app.float.hm_corner_radius_level12')` */
  static readonly cornerRadiusLevel12: number = 24;
  /** 26vp — `$r('app.float.hm_corner_radius_level13')` */
  static readonly cornerRadiusLevel13: number = 26;
  /** 32vp — `$r('app.float.hm_corner_radius_level16')` */
  static readonly cornerRadiusLevel16: number = 32;
  /** 36vp — `$r('app.float.hm_corner_radius_level18')` */
  static readonly cornerRadiusLevel18: number = 36;
  /** 4vp — `$r('app.float.hm_corner_radius_level2')` */
  static readonly cornerRadiusLevel2: number = 4;
  /** 6vp — `$r('app.float.hm_corner_radius_level3')` */
  static readonly cornerRadiusLevel3: number = 6;
  /** 8vp — `$r('app.float.hm_corner_radius_level4')` */
  static readonly cornerRadiusLevel4: number = 8;
  /** 10vp — `$r('app.float.hm_corner_radius_level5')` */
  static readonly cornerRadiusLevel5: number = 10;
  /** 12vp — `$r('app.float.hm_corner_radius_level6')` */
  static readonly cornerRadiusLevel6: number = 12;
  /** 14vp — `$r('app.float.hm_corner_radius_level7')` */
  static readonly cornerRadiusLevel7: number = 14;
  /** 16vp — `$r('app.float.hm_corner_radius_level8')` */
  static readonly cornerRadiusLevel8: number = 16;
  /** 18vp — `$r('app.float.hm_corner_radius_level9')` */
  static readonly cornerRadiusLevel9: number = 18;
  /** 0vp — `$r('app.float.hm_corner_radius_none')` */
  static readonly cornerRadiusNone: number = 0;
  /** 12vp — `$r('app.float.hm_dock_lift')` */
  static readonly dockLift: number = 12;
  /** 16fp — `$r('app.float.hm_font_size_body_l')` */
  static readonly fontSizeBodyL: number = 16;
  /** 14fp — `$r('app.float.hm_font_size_body_m')` */
  static readonly fontSizeBodyM: number = 14;
  /** 12fp — `$r('app.float.hm_font_size_body_s')` */
  static readonly fontSizeBodyS: number = 12;
  /** 12fp — `$r('app.float.hm_font_size_caption_l')` */
  static readonly fontSizeCaptionL: number = 12;
  /** 10fp — `$r('app.float.hm_font_size_caption_m')` */
  static readonly fontSizeCaptionM: number = 10;
  /** 8fp — `$r('app.float.hm_font_size_caption_s')` */
  static readonly fontSizeCaptionS: number = 8;
  /** 56fp — `$r('app.float.hm_font_size_display_l')` */
  static readonly fontSizeDisplayL: number = 56;
  /** 48fp — `$r('app.float.hm_font_size_display_m')` */
  static readonly fontSizeDisplayM: number = 48;
  /** 38fp — `$r('app.float.hm_font_size_display_s')` */
  static readonly fontSizeDisplayS: number = 38;
  /** 18fp — `$r('app.float.hm_font_size_subtitle_l')` */
  static readonly fontSizeSubtitleL: number = 18;
  /** 16fp — `$r('app.float.hm_font_size_subtitle_m')` */
  static readonly fontSizeSubtitleM: number = 16;
  /** 14fp — `$r('app.float.hm_font_size_subtitle_s')` */
  static readonly fontSizeSubtitleS: number = 14;
  /** 30fp — `$r('app.float.hm_font_size_title_l')` */
  static readonly fontSizeTitleL: number = 30;
  /** 24fp — `$r('app.float.hm_font_size_title_m')` */
  static readonly fontSizeTitleM: number = 24;
  /** 20fp — `$r('app.float.hm_font_size_title_s')` */
  static readonly fontSizeTitleS: number = 20;
  /** 16vp — `$r('app.float.hm_icon_size_16')` */
  static readonly iconSize16: number = 16;
  /** 20vp — `$r('app.float.hm_icon_size_20')` */
  static readonly iconSize20: number = 20;
  /** 24vp — `$r('app.float.hm_icon_size_24')` */
  static readonly iconSize24: number = 24;
  /** 16vp — `$r('app.float.hm_inline_gap_loose_mobile')` */
  static readonly inlineGapLooseMobile: number = 16;
  /** 12vp — `$r('app.float.hm_inline_gap_mobile')` */
  static readonly inlineGapMobile: number = 12;
  /** 4vp — `$r('app.float.hm_inline_gap_tight_mobile')` */
  static readonly inlineGapTightMobile: number = 4;
  /** 30vp — `$r('app.float.hm_material_blur')` */
  static readonly materialBlur: number = 30;
  /** 80vp — `$r('app.float.hm_material_blur_pill')` */
  static readonly materialBlurPill: number = 80;
  /** 12vp — `$r('app.float.hm_material_blur_titlebar_base')` */
  static readonly materialBlurTitlebarBase: number = 12;
  /** 0vp — `$r('app.float.hm_padding_level0')` */
  static readonly paddingLevel0: number = 0;
  /** 2vp — `$r('app.float.hm_padding_level1')` */
  static readonly paddingLevel1: number = 2;
  /** 20vp — `$r('app.float.hm_padding_level10')` */
  static readonly paddingLevel10: number = 20;
  /** 22vp — `$r('app.float.hm_padding_level11')` */
  static readonly paddingLevel11: number = 22;
  /** 24vp — `$r('app.float.hm_padding_level12')` */
  static readonly paddingLevel12: number = 24;
  /** 26vp — `$r('app.float.hm_padding_level13')` */
  static readonly paddingLevel13: number = 26;
  /** 32vp — `$r('app.float.hm_padding_level16')` */
  static readonly paddingLevel16: number = 32;
  /** 4vp — `$r('app.float.hm_padding_level2')` */
  static readonly paddingLevel2: number = 4;
  /** 6vp — `$r('app.float.hm_padding_level3')` */
  static readonly paddingLevel3: number = 6;
  /** 8vp — `$r('app.float.hm_padding_level4')` */
  static readonly paddingLevel4: number = 8;
  /** 10vp — `$r('app.float.hm_padding_level5')` */
  static readonly paddingLevel5: number = 10;
  /** 12vp — `$r('app.float.hm_padding_level6')` */
  static readonly paddingLevel6: number = 12;
  /** 14vp — `$r('app.float.hm_padding_level7')` */
  static readonly paddingLevel7: number = 14;
  /** 16vp — `$r('app.float.hm_padding_level8')` */
  static readonly paddingLevel8: number = 16;
  /** 18vp — `$r('app.float.hm_padding_level9')` */
  static readonly paddingLevel9: number = 18;
  /** 360vp — `$r('app.float.hm_page_canvas_width_mobile')` */
  static readonly pageCanvasWidthMobile: number = 360;
  /** 328vp — `$r('app.float.hm_page_content_width_mobile')` */
  static readonly pageContentWidthMobile: number = 328;
  /** 16vp — `$r('app.float.hm_page_padding_mobile')` */
  static readonly pagePaddingMobile: number = 16;
  /** 28vp — `$r('app.float.hm_page_padding_mobile_bottom')` */
  static readonly pagePaddingMobileBottom: number = 28;
  /** 36vp — `$r('app.float.hm_page_padding_mobile_top')` */
  static readonly pagePaddingMobileTop: number = 36;
  /** 16vp — `$r('app.float.hm_section_gap_mobile')` */
  static readonly sectionGapMobile: number = 16;
  /** 8vp — `$r('app.float.hm_section_gap_tight_mobile')` */
  static readonly sectionGapTightMobile: number = 8;
  /** 56vp — `$r('app.float.hm_tabbar_h')` */
  static readonly tabbarH: number = 56;
  /** 28vp — `$r('app.float.hm_tabbar_indicator')` */
  static readonly tabbarIndicator: number = 28;
  /** 16vp — `$r('app.float.hm_tabbar_top_pad')` */
  static readonly tabbarTopPad: number = 16;
  /** 160vp — `$r('app.float.hm_tabbar_width_2')` */
  static readonly tabbarWidth2: number = 160;
  /** 236vp — `$r('app.float.hm_tabbar_width_3')` */
  static readonly tabbarWidth3: number = 236;
  /** 328vp — `$r('app.float.hm_tabbar_width_4')` */
  static readonly tabbarWidth4: number = 328;
  /** 328vp — `$r('app.float.hm_tabbar_width_5')` */
  static readonly tabbarWidth5: number = 328;
  /** 264vp — `$r('app.float.hm_tabbar_width_multi')` */
  static readonly tabbarWidthMulti: number = 264;
  /** 264vp — `$r('app.float.hm_tabbar_width_single')` */
  static readonly tabbarWidthSingle: number = 264;
  /** 8vp — `$r('app.float.hm_text_gap_mobile_left')` */
  static readonly textGapMobileLeft: number = 8;
  /** 2vp — `$r('app.float.hm_text_gap_mobile_top')` */
  static readonly textGapMobileTop: number = 2;
  /** 32vp — `$r('app.float.hm_titlebar_fade')` */
  static readonly titlebarFade: number = 32;
  /** 8vp — `$r('app.float.hm_titlebar_gap')` */
  static readonly titlebarGap: number = 8;
  /** 52vp — `$r('app.float.hm_titlebar_layer_normal')` */
  static readonly titlebarLayerNormal: number = 52;
  /** 67vp — `$r('app.float.hm_titlebar_layer_secondary')` */
  static readonly titlebarLayerSecondary: number = 67;
  /** 12vp — `$r('app.float.hm_titlebar_pad_top')` */
  static readonly titlebarPadTop: number = 12;
  /** 124vp — `$r('app.float.hm_titlebar_panel')` */
  static readonly titlebarPanel: number = 124;
  /** 40vp — `$r('app.float.hm_titlebar_row')` */
  static readonly titlebarRow: number = 40;
  /** 40vp — `$r('app.float.hm_touch_target')` */
  static readonly touchTarget: number = 40;
  /** 36vp — `$r('app.float.hm_touch_target_min')` */
  static readonly touchTargetMin: number = 36;
}
