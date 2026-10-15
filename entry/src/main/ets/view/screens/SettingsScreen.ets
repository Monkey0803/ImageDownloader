import { TasksViewModel } from '../../viewmodel/TasksViewModel';
import { DeviceViewModel } from '../../viewmodel/DeviceViewModel';
import { SettingsViewModel } from '../../viewmodel/SettingsViewModel';
import {
  DOWNLOAD_LOCATIONS, MATERIAL_LEVELS, MATERIAL_TYPES, PICTURE_QUALITIES, THEME_CHOICES
} from '../../model/SettingsOptions';
import { Font, Layout, Palette, Space } from '../../theme/Tokens';
import { ScreenMetrics } from '../../theme/Metrics';
import { Card, ListRow, SectionHead, SettingSelect, StackedRow, TitleBar } from '../Widgets';
import { SCREEN_INSETS } from '../../theme/Metrics';

/**
 * 「设置」页：外观 / 系统特性 / 下载 / 数据四节。
 *
 * 从 Index 的 `settingsScreen()` / `sliderRow()` 搬过来。这一页是「一堆行 + 一行一个控件」，
 * 所以每一行的**档位表、当前下标、当前名字、说明文字**全部来自 ViewModel，
 * 组件里只剩「这行长什么样」——原来五行各自写了一遍 `choiceIndex/choiceOf/choiceLabels`。
 *
 * 三个 ViewModel 的分工：
 * - `settings`：主题 / 材质 / 图片质量 / 下载位置 / 占用 / 清理与清空；
 * - `device`：智感握姿 / 防窥保护（只有它们要跟系统订阅打交道）；
 * - `tasks`：只有「同时下载数量」一行 —— 并发数属于下载队列，不属于外观设置。
 */
@ComponentV2
export struct SettingsScreen {
  @Require @Param settings: SettingsViewModel;
  @Require @Param device: DeviceViewModel;
  @Require @Param tasks: TasksViewModel;

  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。
  // 安全区改读 V2 单例：@StorageProp 在 @ComponentV2 里非法（报 10905339）。

  @Builder
  private sliderRow() {
    Slider({ value: this.tasks.concurrency, min: 1, max: 10, step: 1, style: SliderStyle.OutSet })
      .width('100%')
      .trackThickness(4)
      .selectedColor(Palette.brand)
      .trackColor(Palette.cardSunken)
      .blockColor(Palette.white)
      .blockBorderWidth(5)
      .blockBorderColor(Palette.brand)
      .onChange((value: number): void => {
        this.tasks.setConcurrency(value);
      })
  }

  /** 防窥保护那一行的说明：「开关开了」和「真的在保护我」必须能分清。 */
  private antiPeepHint(): string {
    if (!this.device.antiPeep) {
      return '检测到他人窥视时隐藏内容并顶部提醒';
    }
    return this.device.antiPeepReady()
      ? '已接入 · 检测到窥视时立即隐藏内容'
      : '未生效：' + this.device.antiPeepProblem;
  }

  /**
   * 智感握姿那一行的说明。
   *
   * 这一行原来**没有** aux，靠勾选时那一次 Toast 说「开没生效」；现在 Toast 去掉了，
   * 那句就必须落在这里 —— 否则设备不支持时用户只会看到一个开着的开关，什么都不知道。
   * 与「防窥保护」那一行同一个套路：关着写它能做什么，开着写「已接入」或「未生效：原因」。
   */
  private gripHint(): string {
    if (!this.device.grip) {
      return '主操作跟随握持手：左手握持时下载按钮换到左侧';
    }
    return this.device.gripSupported
      ? '已接入 · 主操作跟随握持手'
      : '未生效：' + this.device.gripProblem;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: Space.s20 }) {
          Column({ space: Space.s10 }) {
            SectionHead({ heading: '外观' })
            Card({ pad: 0 }) {
              // 切深浅色时图标跟着换（sun ↔ moon），所以 ListRow.glyph 必须是 @Prop。
              ListRow({
                glyph: this.settings.themeMode === 'dark' ? 'moon' : 'sun',
                heading: '主题'
              }) {
                // 与材质两行同一个控件：当前主题写在胶囊上，原来那句「跟随系统 / 固定为深色」
                // 的 aux 就成了重复信息，一并去掉。
                SettingSelect({
                  options: THEME_CHOICES.selectOptions(),
                  selectedIndex: THEME_CHOICES.index(this.settings.themeMode),
                  label: THEME_CHOICES.label(this.settings.themeMode),
                  onPick: (index: number): void => {
                    this.settings.pickTheme(index);
                  }
                })
              }
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: Space.s10 }) {
            SectionHead({ heading: '系统特性', meta: 'HarmonyOS' })
            Card({ pad: 0 }) {
              Column() {
                ListRow({
                  glyph: 'sparkle',
                  heading: '沉浸光感'
                }) {
                  Toggle({ type: ToggleType.Switch, isOn: this.settings.lightEffect })
                    .selectedColor(Palette.brand)
                    .onChange((value: boolean): void => {
                      this.settings.setLightEffect(value);
                    })
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'layers',
                  heading: '材质类型'
                }) {
                  // 和下面「沉浸光感材质」同一个控件：三档用分段控件会挤，
                  // 而且系统设置里这类「当前值 + 下拉」本来就是 Select 的形态。
                  SettingSelect({
                    options: MATERIAL_TYPES.selectOptions(),
                    selectedIndex: this.settings.materialTypeIndex(),
                    label: MATERIAL_TYPES.label(this.settings.materialType),
                    onPick: (index: number): void => {
                      this.settings.pickMaterialType(index);
                    }
                  })
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'sliders',
                  heading: '沉浸光感材质'
                }) {
                  SettingSelect({
                    options: MATERIAL_LEVELS.selectOptions(),
                    selectedIndex: this.settings.materialLevelIndex(),
                    label: MATERIAL_LEVELS.label(this.settings.materialLevel),
                    onPick: (index: number): void => {
                      this.settings.pickMaterialLevel(index);
                    }
                  })
                }
              }
              .width('100%')
            }

            Card({ pad: 0 }) {
              Column() {
                ListRow({
                  glyph: 'grip',
                  heading: '智感握姿',
                  // 不再弹 Toast，所以「开没生效」这句话必须常驻在这一行（见 gripHint）。
                  aux: this.gripHint()
                }) {
                  Toggle({ type: ToggleType.Switch, isOn: this.device.grip })
                    .selectedColor(Palette.brand)
                    .onChange((value: boolean): void => {
                      this.device.pickGrip(value);
                    })
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                // 这一行保留辅助说明（智感握姿那行没有）：握姿的生效状态在发现页有胶囊可看，
                // 防窥的「已接入」没有第二个落点，必须在行内说清楚。
                ListRow({
                  glyph: 'shield',
                  heading: '防窥保护',
                  aux: this.antiPeepHint()
                }) {
                  Toggle({ type: ToggleType.Switch, isOn: this.device.antiPeep })
                    .selectedColor(Palette.brand)
                    .onChange((value: boolean): void => {
                      this.device.pickAntiPeep(value);
                    })
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: Space.s10 }) {
            SectionHead({ heading: '下载' })
            Card({ pad: 0 }) {
              Column() {
                StackedRow({
                  glyph: 'download',
                  heading: '同时下载数量',
                  aux: '超出的任务自动排队，范围 1–10'
                }) {
                  this.sliderRow()
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'folder',
                  heading: '文件名来源',
                  aux: '优先用服务器返回的文件名，其次用网页描述'
                }) {
                  Text('服务器优先')
                    .fontSize(Font.aux)
                    .fontColor(Palette.fontSecondary)
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'image',
                  heading: '下载图片质量',
                  // aux 跟着档位走，讲清这一档会取网页里的哪个地址。
                  aux: this.settings.qualityHint()
                }) {
                  // 与材质两行同一个下拉控件：三档「原图优先 / 网页显示图 / 全部」。
                  // 没有「取消选择」的路径，所以不需要 locationRevision 那种重建号。
                  SettingSelect({
                    options: PICTURE_QUALITIES.selectOptions(),
                    selectedIndex: this.settings.qualityIndex(),
                    label: this.settings.qualityLabel(),
                    onPick: (index: number): void => {
                      this.settings.pickPictureQuality(index);
                    }
                  })
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'archive',
                  heading: '下载位置',
                  // aux 跟着档位走：相册 / 自定义目录各有一句，投递失败时被原因顶掉。
                  aux: this.settings.locationHint()
                }) {
                  // 与材质两行同一个下拉控件：三档「应用文件 / 系统相册 / 自定义目录」。
                  // 选「自定义目录」时会先拉起系统目录选择器，选到了才真正落档。
                  SettingSelect({
                    options: DOWNLOAD_LOCATIONS.selectOptions(),
                    selectedIndex: this.settings.locationIndex(),
                    label: this.settings.locationLabel(),
                    // 选了自定义目录又在选择器里取消时，靠这个号把控件刷回已提交的档位。
                    revision: this.settings.locationRevision,
                    onPick: (index: number): void => {
                      this.settings.pickDownloadLocation(index);
                    }
                  })
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: Space.s10 }) {
            // 写盘失败时这句话顶掉占用说明：状态可能保不住，比「占用多少」重要得多。
            SectionHead({
              heading: '数据',
              meta: this.settings.saveProblem.length > 0 ? this.settings.saveProblem : this.settings.usedLabel
            })
            Card({ pad: 0 }) {
              Column() {
                ListRow({
                  glyph: 'trash',
                  heading: '清理临时文件',
                  aux: '打包中断后残留在暂存目录的图片',
                  onAction: (): void => {
                    this.settings.cleanTemp();
                  }
                }) {
                  Text('清理')
                    .fontSize(Font.aux)
                    .fontColor(Palette.brand)
                }

                Divider().color(Palette.divider).margin({ left: 60 })

                ListRow({
                  glyph: 'xCircle',
                  heading: '清空全部下载记录',
                  aux: '删除应用内的文件与记录，已导出的副本不受影响',
                  onAction: (): void => {
                    this.settings.confirmClearAll();
                  }
                }) {
                  Text('清空')
                    .fontSize(Font.aux)
                    .fontColor(Palette.warning)
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Text('图片下载管理 · 1.0.0')
            .fontSize(Font.caption)
            .fontColor(Palette.fontTertiary)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: ScreenMetrics.height() })
        .padding({
          left: Layout.pagePad,
          right: Layout.pagePad,
          top: ScreenMetrics.topInset(SCREEN_INSETS.safeTop, false),
          bottom: ScreenMetrics.bottomInset(SCREEN_INSETS.safeBottom, 0)
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      TitleBar({ heading: '设置', layer: Layout.tbLayerNormal })
    }
    .width('100%')
    .height('100%')
  }
}
