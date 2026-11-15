import { common, wantAgent, WantAgent } from "@kit.AbilityKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { BusinessError } from "@kit.BasicServicesKit";
import notificationManager from "@ohos.notificationManager";
import Want from "@ohos.app.ability.Want";

/**
 * dataTransfer 长时任务封装（后台下载用），实现严格对照官方文档：
 * - 申请成功后系统自动挂出任务通知，应用不得用同 id 通知覆盖它，
 *   否则系统视为通知被删除并自动停止任务；
 * - dataTransfer 首次进度更新超过 10 分钟未上报会被系统取消
 *   (SYSTEM_CANCEL_DATA_TRANSFER_NOT_UPDATE)，
 *   有真实进度时按文档 updateProcess 示例经实况窗通知更新。
 */
export class BackgroundTask {
  private static instance: BackgroundTask | null = null;

  static getInstance(): BackgroundTask {
    if (!BackgroundTask.instance) {
      BackgroundTask.instance = new BackgroundTask();
    }
    return BackgroundTask.instance;
  }

  private running: boolean = false;
  private wanted: boolean = false;
  private queue: Promise<void> = Promise.resolve();
  private notificationId: number = -1;
  private lastProgress: number = -1;
  private remaining: string = '';
  private lastPublish: number = 0;
  private keepAliveTimer: number = -1;
  /// 已 publish 的进度通知 id（downloadTemplate 与任务通知共用 id，但
  /// 系统移除任务通知不会移除我们 publish 的进度通知，需自行跟踪清理）
  private progressNotificationIds: number[] = [];
  /// Stage 模型下长时任务只能由 UIAbility 申请；getContext(this) 仅在
  /// ArkUI 组件内有效，纯 TS 类里返回 undefined，必须由插件注入 context
  private uiContext: common.UIAbilityContext | null = null;

  private constructor() {
    this.listenSystemCancel();
  }

  /// 由 FlutterPlugin（onAttachedToAbility）注入，见 HarmonyChannel
  static init(context: common.UIAbilityContext): void {
    BackgroundTask.getInstance().uiContext = context;
  }

  isRunning(): boolean {
    return this.running;
  }

  setRunning(wanted: boolean): Promise<void> {
    if (this.wanted === wanted) {
      return this.queue;
    }
    this.wanted = wanted;
    this.queue = this.queue.then(async (): Promise<void> => {
      if (this.wanted === this.running) {
        return;
      }
      if (this.wanted) {
        await this.start();
        // 申请失败要清 wanted，否则后续 setRunning(true) 会被幂等门吞掉
        if (!this.running) {
          this.wanted = false;
        }
      } else {
        await this.stop();
      }
    });
    return this.queue;
  }

  updateProgress(progress: number, remaining: string): void {
    if (!this.running) {
      return;
    }
    this.lastProgress = progress;
    this.remaining = remaining;
    this.publish();
  }

  private getContext(): common.UIAbilityContext {
    if (this.uiContext === null) {
      throw new Error("BackgroundTask not initialized: call BackgroundTask.init(uiAbilityContext) first");
    }
    return this.uiContext;
  }

  private async start(): Promise<void> {
    const context = this.getContext();
    try {
      await this.doStart(context);
    } catch (error) {
      const code = (error as BusinessError).code;
      // 9800005: 同一 UIAbility 已存在未结束的长时任务（进程重启后内部
      // 状态丢失、或上次申请已被系统受理但标志未落地）。
      // 先停掉残留任务再重试一次。
      if (code === 9800005) {
        try {
          await backgroundTaskManager.stopBackgroundRunning(context);
          await this.doStart(context);
        } catch (retryError) {
          console.error("BackgroundTask",
            `start retry failed, code: ${(retryError as BusinessError).code}, msg: ${(retryError as BusinessError).message}`);
        }
      } else {
        console.error("BackgroundTask",
          `start failed, code: ${code}, msg: ${(error as BusinessError).message}`);
      }
    }
  }

  private async doStart(context: common.UIAbilityContext): Promise<void> {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name,
        } as Want,
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    const wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
    const res = await backgroundTaskManager.startBackgroundRunning(
      context, ["dataTransfer"], wantAgentObj,
    );
    this.notificationId = res?.notificationId ?? -1;
    this.running = true;
    this.lastProgress = -1;
    this.lastPublish = 0;
    this.progressNotificationIds = [];
    this.startKeepAlive();
    // 不在此处 publish：系统申请成功后会自行挂出任务通知，
    // 应用立即发同 id 通知会顶掉它并导致任务被系统停止
    console.info("BackgroundTask", "started (dataTransfer), notificationId: " + this.notificationId);
  }

  private async stop(): Promise<void> {
    if (this.keepAliveTimer !== -1) {
      clearInterval(this.keepAliveTimer);
      this.keepAliveTimer = -1;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.getContext());
      console.info("BackgroundTask", "stopped");
    } catch (error) {
      console.error("BackgroundTask",
        `stop failed, code: ${(error as BusinessError).code}, msg: ${(error as BusinessError).message}`);
    }
    this.running = false;
    this.notificationId = -1;
    this.lastProgress = -1;
    this.lastPublish = 0;
    this.cancelProgressNotifications();
  }

  /// 统一清理进度通知。dataTransfer 任务通知随任务结束被系统移除，
  /// 但 downloadTemplate 进度通知是我们自己 publish 的，必须自行撤销。
  /// 幂等：重复调用/无通知时静默返回。
  private cancelProgressNotifications(): void {
    const ids = this.progressNotificationIds;
    this.progressNotificationIds = [];
    for (const id of ids) {
      notificationManager.cancel(id).catch((error: BusinessError): void => {
        // 1600002: 通知已不存在，视为清理成功
        if (error.code !== 1600002) {
          console.error("BackgroundTask",
            `cancel notification failed, id: ${id}, code: ${error.code}, msg: ${error.message}`);
        }
      });
    }
  }

  private startKeepAlive(): void {
    this.keepAliveTimer = setInterval((): void => {
      this.publish();
    }, 4 * 60 * 1000);
  }

  private listenSystemCancel(): void {
    try {
      backgroundTaskManager.on("continuousTaskCancel",
        (info: backgroundTaskManager.ContinuousTaskCancelInfo) => {
          if (info.id === this.notificationId) {
            console.warn("BackgroundTask", `cancelled by system, reason: ${info.reason}`);
            this.running = false;
            this.notificationId = -1;
            if (this.keepAliveTimer !== -1) {
              clearInterval(this.keepAliveTimer);
              this.keepAliveTimer = -1;
            }
            this.cancelProgressNotifications();
          }
        });
    } catch (error) {
      console.error("BackgroundTask", `listen cancel failed: ${(error as BusinessError).message}`);
    }
  }

  /// 按文档 updateProcess 示例更新实况窗进度，3s 节流。
  /// 三方应用不能直接发 NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW（系统应用
  /// 专属，会报 202）；任务申请成功后系统已代为创建系统实况窗，三方只
  /// 需携带同 id + downloadTemplate 模板 publish 即可更新其进度。
  private publish(): void {
    if (!this.running || this.notificationId < 0 || this.lastProgress < 0) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastPublish < 3 * 1000) {
      return;
    }
    this.lastPublish = now;
    const progress: number = Math.floor(this.lastProgress);
    const request: notificationManager.NotificationRequest = {
      id: this.notificationId,
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      // 内容占位：实际展示样式由 downloadTemplate 模板渲染
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '后台下载',
          text: `进度 ${progress}%`,
        },
      },
      template: {
        name: 'downloadTemplate',
        data: {
          title: '离线缓存中...',
          fileName: this.remaining,
          progressValue: progress,
        },
      },
    };
    notificationManager.publish(request).then((): void => {
      if (!this.progressNotificationIds.includes(this.notificationId)) {
        this.progressNotificationIds.push(this.notificationId);
      }
    }).catch((error: BusinessError): void => {
      console.error("BackgroundTask",
        `publish progress failed, code: ${error.code}, msg: ${error.message}`);
    });
  }
}
